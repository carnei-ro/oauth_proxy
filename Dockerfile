FROM leandrocarneiro/openresty

COPY microsoft_proxy.conf /etc/nginx/conf.d/default.conf
COPY microsoft.lua /etc/nginx/conf.d/microsoft.lua
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
