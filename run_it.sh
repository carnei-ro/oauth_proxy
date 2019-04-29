IMAGE=leandrocarneiro/oauth_proxy:microsoft
docker rm -vf oauth_proxy ;
docker run -it --name=oauth_proxy --rm -p 80:80 \
	-e CLIENT_ID='00000000-0000-0000-0000-000000000000' \
	-e CLIENT_SECRET='abcDEFG123wxyzHIJ12:-:#' \
	-e DOMAIN='outlook.com,hotmail.com' \
	-e TOKEN_SECRET='someRandomHash' \
	-e UPSTREAM_SITE='http://192.168.2.176:8080' \
	${IMAGE};
