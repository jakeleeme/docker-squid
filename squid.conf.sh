#!/usr/bin/bash

proxy_servers=$(wget -qO - http://mirrors.ubuntu.com/mirrors.txt)

cat <<EOF
http_port 3128

cache_mem 4 GB
maximum_object_size_in_memory 4 MB
memory_replacement_policy heap LRU

cache_dir aufs ${SQUID_CACHE_DIR} 16384 16 256
cache_replacement_policy heap GDSF
cache_swap_low 94
cache_swap_high 95
maximum_object_size 1 GB

# Example rule allowing access from your local networks.
# Adapt to list your (internal) IP networks from where browsing
# should be allowed
acl localnet src 10.0.0.0/8     # RFC1918 possible internal network
acl localnet src 172.16.0.0/12  # RFC1918 possible internal network
acl localnet src 192.168.0.0/16 # RFC1918 possible internal network
acl localnet src fc00::/7       # RFC 4193 local private network range
acl localnet src fe80::/10      # RFC 4291 link-local (directly plugged) machines

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

# Example rule allowing access from your local networks.
# Adapt localnet in the ACL section to list your (internal) IP networks
# from where browsing should be allowed
http_access allow localnet
http_access allow localhost

EOF

cat <<EOF
# Caching for archive.ubuntu.com.local
acl ubuntu_archive_mirror dstdomain archive.ubuntu.com archive.ubuntu.com.local
acl ubuntu_archive_path urlpath_regex ^/ubuntu/

EOF

i=0
for proxy in $proxy_servers; do
  i=$((i + 1))
  echo "# ${proxy}"
  proxy_name=ubuntu_archive_peer${i}
  proxy_host=$(echo "$proxy" | sed -r 's@http://([^/]+?)/.*$@\1@')
  proxy_hostname=$(echo "$proxy_host" | sed -r 's/:[0-9]*$//')
  if [[ "$proxy_hostname" == 'archive.ubuntu.com' ]]; then
    continue
  fi
  proxy_port=$(echo "$proxy_hostname" | sed -rn 's/^.*[^:]:([0-9]+)$/\1/p')
  if [[ x"$proxy_port" == "x" ]]; then
    proxy_port=80
  fi
  proxy_path=$(echo "$proxy" | sed -r 's@http://[^/]+(/.*)$@\1@')
  if [[ "$proxy_path" == '/ubuntu/' ]]; then
    echo "acl $proxy_name dstdomain $proxy_hostname"
    echo "acl ubuntu_archive_mirror dstdomain $proxy_hostname"
    echo "cache_peer $proxy_hostname parent $proxy_port 0 no-query weighted-round-robin weight=2 originserver allow-miss forceddomain=${proxy_host} max-conn=4 name=$proxy_name"
    echo "cache_peer_access $proxy_name deny !ubuntu_archive_path"
    echo "cache_peer_access $proxy_name deny $proxy_name"
    echo "cache_peer_access $proxy_name allow ubuntu_archive_mirror"
    echo "cache_peer_access $proxy_name deny all"
  else
    echo "acl $proxy_name url_regex ^${proxy}.*$"
    echo "http_access deny $proxy_name"
  fi
  echo ''
done

cat <<EOF
# archive.ubuntu.com
cache_peer archive.ubuntu.com parent 80 0 default originserver forceddomain=archive.ubuntu.com max-conn=1 name=ubuntu_archive_origin
cache_peer_access ubuntu_archive_origin allow ubuntu_archive_mirror
cache_peer_access ubuntu_archive_origin deny all

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

EOF

cat <<EOF
refresh_pattern ^ftp:   1440  20% 10080
refresh_pattern ^gopher:  1440  0%  1440
refresh_pattern -i (/cgi-bin/|\?) 0 0%  0
refresh_pattern (Release|Packages(.gz)*)$      0       20%     2880
refresh_pattern .   0 20% 4320

# And finally deny all other access to this proxy
http_access deny all
EOF
