#!/bin/bash

# Auto-deploy hook for $DOMAIN
cp "/etc/letsencrypt/live/$OME_HOST_IP/cert.pem" "$OME_DOCKER_HOME/conf/cert.crt"
cp "/etc/letsencrypt/live/$OME_HOST_IP/privkey.pem" "$OME_DOCKER_HOME/conf/cert.key"
cp "/etc/letsencrypt/live/$OME_HOST_IP/chain.pem" "$OME_DOCKER_HOME/conf/cert.ca-bundle"
cp "/etc/letsencrypt/live/$OME_HOST_IP/fullchain.pem" "$OME_DOCKER_HOME/conf/fullchain.pem"
chmod 640 "$OME_DOCKER_HOME/conf/cert.key"
docker restart ome