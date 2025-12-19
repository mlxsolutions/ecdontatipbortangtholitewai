#!/bin/bash

# Auto-deploy hook for $DOMAIN
cp "/etc/letsencrypt/live/$DOMAIN/cert.pem" "$OME_DOCKER_HOME/conf/cert.crt"
cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "$OME_DOCKER_HOME/conf/cert.key"
cp "/etc/letsencrypt/live/$DOMAIN/chain.pem" "$OME_DOCKER_HOME/conf/cert.ca-bundle"
cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$OME_DOCKER_HOME/conf/fullchain.pem"
chmod 640 "$OME_DOCKER_HOME/conf/cert.key"
docker restart ome