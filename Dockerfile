FROM leandrocarneiro/openresty

COPY zoho_proxy.conf /etc/nginx/conf.d/default.conf
COPY zoho.lua /etc/nginx/conf.d/zoho.lua
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
