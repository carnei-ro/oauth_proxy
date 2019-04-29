FROM leandrocarneiro/openresty

COPY google_proxy.conf /etc/nginx/conf.d/default.conf
COPY google.lua /etc/nginx/conf.d/google.lua
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
