IMAGE=leandrocarneiro/oauth_proxy:zoho
docker rm -vf oauth_proxy ;
docker run -it --name=oauth_proxy --rm -p 80:80 \
	-e CLIENT_ID='1000.ABCDEFGHIJKLMNOPQRSTUVWXYZ1234' \
	-e CLIENT_SECRET='0123456789abcdef0123456789abcdef0123456789' \
	-e DOMAIN='carnei.ro' \
	-e TOKEN_SECRET='someRandomHash' \
	-e UPSTREAM_SITE='http://192.168.2.176:8080' \
	${IMAGE};
