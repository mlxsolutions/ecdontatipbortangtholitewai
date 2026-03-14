#!/bin/bash

# Auto-deploy
cp "/etc/letsencrypt/live/$OME_HOST_IP/cert.pem" "$OME_DOCKER_HOME/conf/cert.crt"
cp "/etc/letsencrypt/live/$OME_HOST_IP/privkey.pem" "$OME_DOCKER_HOME/conf/cert.key"
cp "/etc/letsencrypt/live/$OME_HOST_IP/chain.pem" "$OME_DOCKER_HOME/conf/cert.ca-bundle"
cp "/etc/letsencrypt/live/$OME_HOST_IP/fullchain.pem" "$OME_DOCKER_HOME/conf/fullchain.pem"
chmod 777 -R "$OME_DOCKER_HOME/conf"
docker restart ome

cp "/etc/letsencrypt/live/$OME_HOST_IP/cert.pem" "/home/ubuntu/mlx_thumb_server/certs/cert.crt"
cp "/etc/letsencrypt/live/$OME_HOST_IP/privkey.pem" "/home/ubuntu/mlx_thumb_server/certs/cert.key"
cp "/etc/letsencrypt/live/$OME_HOST_IP/chain.pem" "/home/ubuntu/mlx_thumb_server/certs/cert.ca-bundle"
cp "/etc/letsencrypt/live/$OME_HOST_IP/fullchain.pem" "/home/ubuntu/mlx_thumb_server/certs/fullchain.pem"
chmod 777 -R /home/ubuntu/mlx_thumb_server/certs
cd /home/ubuntu/mlx_thumb_server
docker compose down
docker compose up -d