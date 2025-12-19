#!/bin/bash

docker stop ome
docker rm ome
docker run -d --name ome \
  -e OME_HOST_IP="$OME_HOST_IP" \
  -e PUBLIC_IPV4="$PUBLIC_IPV4" \
  -e API_ACCESS_TOKEN="$API_ACCESS_TOKEN" \
  -e OVT_WORKER_COUNT="$OVT_WORKER_COUNT" \
  -e WEBRTC_SIGNALLING_WORKER_COUNT="$WEBRTC_SIGNALLING_WORKER_COUNT" \
  -v "$OME_DOCKER_HOST/conf":/opt/ovenmediaengine/bin/origin_conf \
  -v "$OME_DOCKER_HOST/logs":/var/log/ovenmediaengine \
  -v "$OME_DOCKER_HOST/rec":/mnt/record \
  -p 1935:1935 \
  -p 9999:9999/udp \
  -p 9000:9000 \
  -p 3334:3334 \
  -p 4334:4334 \
  -p 3478:3478 \
  -p 8082:8082 \
  -p 6379:6379 \
  -p 20081:20081 \
  -p 10000-10002:10000-10002/udp \
  airensoft/ovenmediaengine:latest
echo "✅ OME is up and running!"