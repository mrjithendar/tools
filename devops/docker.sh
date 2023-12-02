#!/bin/bash 

echo "::::INSTALLING DOCKER::::"
sudo yum check-update
curl -fsSL https://get.docker.com/ | sh
systemctl enable docker && systemctl restart docker
echo -e "Docker installed successfully"

