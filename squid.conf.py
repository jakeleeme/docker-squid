#!/usr/bin/python

from __future__ import division, print_function

import os

try:
  from urlparse import urlparse
except ImportError:
  from urllib import parse as urlparse

ENV = {
  'SQUID_CACHE_DIR': '/var/cache/squid',
}
ENV.update(os.environ)

CONFIG_CHUNK0 = '''\
# Squid normally listens to port 3128
http_port 3128

# Configure memory cache.
cache_mem 4 GB
maximum_object_size_in_memory 4 MB
memory_replacement_policy lru

# Add a disk cache directory.
cache_dir aufs {SQUID_CACHE_DIR} 16384 16 256
cache_replacement_policy heap GDSF
cache_swap_low 94
cache_swap_high 95
maximum_object_size 1 GB

# Leave coredumps in the first cache dir
coredump_dir {SQUID_CACHE_DIR}

# Example rule allowing access from your local networks.
# Adapt to list your (internal) IP networks from where browsing
# should be allowed
acl localnet src 0.0.0.1-0.255.255.255  # RFC 1122 "this" network (LAN)
acl localnet src 10.0.0.0/8   # RFC 1918 local private network (LAN)
acl localnet src 100.64.0.0/10    # RFC 6598 shared address space (CGN)
acl localhet src 169.254.0.0/16   # RFC 3927 link-local (directly plugged) machines
acl localnet src 172.16.0.0/12    # RFC 1918 local private network (LAN)
acl localnet src 192.168.0.0/16   # RFC 1918 local private network (LAN)
acl localnet src fc00::/7         # RFC 4193 local private network range
acl localnet src fe80::/10        # RFC 4291 link-local (directly plugged) machines

acl SSL_ports port 443
acl Safe_ports port 80    # http
acl Safe_ports port 21    # ftp
acl Safe_ports port 443   # https
acl Safe_ports port 70    # gopher
acl Safe_ports port 210   # wais
acl Safe_ports port 1025-65535  # unregistered ports
acl Safe_ports port 280   # http-mgmt
acl Safe_ports port 488   # gss-http
acl Safe_ports port 591   # filemaker
acl Safe_ports port 777   # multiling http
acl CONNECT method CONNECT

# Deny requests to certain unsafe ports
http_access deny !Safe_ports

# Deny CONNECT to other than secure SSL ports
http_access deny CONNECT !SSL_ports

# Only allow cachemgr access from localhost
http_access allow localhost manager
http_access deny manager

# We strongly recommend the following be uncommented to protect innocent
# web applications running on the proxy server who think the only
# one who can access services on "localhost" is a local user
http_access deny to_localhost

# Caching for archive.ubuntu.com.local
acl ubuntu_archive_mirror dstdomain archive.ubuntu.com archive.ubuntu.com.local
acl ubuntu_archive_path urlpath_regex ^/ubuntu/
'''

CONFIG_CHUNK1a = '''\
# {url}
acl {name} dstdomain {hostname}
acl ubuntu_archive_mirror dstdomain {hostname}
cache_peer {hostname} parent {port} 0 no-query weighted-round-robin weight=2 originserver allow-miss forceddomain={hostname} max-conn=4 name={name}
cache_peer_access {name} deny !ubuntu_archive_path
cache_peer_access {name} deny {name}
cache_peer_access {name} allow ubuntu_archive_mirror
cache_peer_access {name} deny all
'''

CONFIG_CHUNK1b = '''\
# {url}
acl {name} url_regex ^{url}.*$
http_access deny {name}
'''

CONFIG_CHUNK2 = '''\
# archive.ubuntu.com
cache_peer archive.ubuntu.com parent 80 0 default originserver forceddomain=archive.ubuntu.com max-conn=1 name=ubuntu_archive_origin
cache_peer_access ubuntu_archive_origin allow ubuntu_archive_mirror
cache_peer_access ubuntu_archive_origin deny all

# Example rule allowing access from your local networks.
# Adapt localnet in the ACL section to list your (internal) IP networks
# from where browsing should be allowed
http_access allow localnet
http_access allow localhost

# And finally deny all other access to this proxy
http_access deny all

# http://bazaar.launchpad.net/~squid-deb-proxy-developers/squid-deb-proxy/trunk/view/head:/squid-deb-proxy.conf
# refresh pattern for debs and udebs
refresh_pattern \.deb$   129600 100% 129600
refresh_pattern \.udeb$   129600 100% 129600
refresh_pattern \.tar\.gz$  129600 100% 129600
refresh_pattern \.tar\.xz$  129600 100% 129600
refresh_pattern \.tar\.bz2$  129600 100% 129600

# always refresh Packages and Release files
refresh_pattern \/(Packages|Sources)(|\.bz2|\.gz|\.xz)$ 0 0% 0 refresh-ims
refresh_pattern \/Release(|\.gpg)$ 0 0% 0 refresh-ims
refresh_pattern \/InRelease$ 0 0% 0 refresh-ims
refresh_pattern \/(Translation-.*)(|\.bz2|\.gz|\.xz)$ 0 0% 0 refresh-ims

#
# Add any of your own refresh_pattern entries above these.
#
refresh_pattern ^ftp:   1440  20% 10080
refresh_pattern ^gopher:  1440  0%  1440
refresh_pattern -i (/cgi-bin/|\?) 0 0%  0
refresh_pattern .   0 20% 4320
'''

print(CONFIG_CHUNK0.format(**ENV))

with open('mirrors.txt') as f:
  i = 0
  for line in f:
    # Skip blank lines and comments
    line = line.strip()
    if line[0] == '#':
      continue
    elif '#' in line:
      line = line[:line.index('#')]

    # Parse proxy URL
    url = urlparse(line)

    # Skip origin server
    if url.hostname == 'archive.ubuntu.com':
      continue

    i += 1
    proxy = {
      'url': line,
      'name': 'ubuntu_archive_peer%03d' % i,
      'scheme': url.scheme or 'http',
      'netloc': url.netloc,
      'path': os.path.normpath(url.path) if url.path else '',
      'username': url.username,
      'password': url.password,
      'hostname': url.hostname,
      'port': url.port or 80,
    }

    # These proxies are most reliable
    is_ubuntu = url.hostname.endswith('.ubuntu.com')
    is_tld_approved = url.hostname.rsplit('.', 1)[-1] in ('org', 'edu')
    is_approved_proxy = is_ubuntu or is_tld_approved

    # Output configuration
    if proxy['path'] == '/ubuntu' and is_approved_proxy:
      print(CONFIG_CHUNK1a.format(**proxy))
    else:
      print(CONFIG_CHUNK1b.format(**proxy))

print(CONFIG_CHUNK2)
