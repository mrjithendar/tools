#!/bin/bash

echo "::::INSTALLING DOCKER COMPOSE::::"
VERSION=$(curl -s https://github.com/docker/compose/tags | grep tar.gz | grep -v '\-rc' | grep nofollow | head -1 |awk -F / '{print $NF}' | awk '{print $1}' | sed -e 's/.tar.gz"//')
curl -s -L "https://github.com/docker/compose/releases/download/${VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /bin/docker-compose
chmod +x /bin/docker-compose
docker-compose --version
if [ $? -eq 127 -o $? -eq 126 ]; then
  echo -e "Installation Failed"
  exit 1
else
  echo -e "Installation Completed"
fi