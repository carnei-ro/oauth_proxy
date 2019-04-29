IMAGE=leandrocarneiro/oauth_proxy:google
docker rm -vf oauth_proxy ;
docker run -it --name=oauth_proxy --rm -p 80:80 \
	-e CLIENT_ID='123456789012-0a12b3c4asdfasdfasdfasdfasdf6547.apps.googleusercontent.com' \
	-e CLIENT_SECRET='AYM-abcdEFGHIJkl-adsf_' \
	-e DOMAIN='gmail.com' \
	-e TOKEN_SECRET='someRandomHash' \
	-e UPSTREAM_SITE='http://192.168.2.176:8080' \
	${IMAGE};
