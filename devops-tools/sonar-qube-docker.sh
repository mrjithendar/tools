#!/bin/bash

## check OS
OS=$(cat /etc/redhat-release | awk {'print $1, $NF'})

if [ "$OS" == "CentOS 8" ]; then
    echo "OS is valid, currently running on: $OS"
else
    echo "Please use CentOS AMI, Currently Running on: $OS"
    exit 1
fi

## user check
if [ $(id -u) -ne 0 ]; then
  echo "You should run as root user"
  exit 1
fi

docker --version

if [ $? -eq 0 ]; then
  echo -e "$(docker --version) found, running sonarqube on docker port 9000"
  docker run -d --name sonar -p 9000:9000 sonarqube:lts-community
  else
    echo -e "installing docker"
    labauto docker.sh
    echo -e "Installed $(docker --version), running sonarqube on docker port 9000"
    docker run -d --name sonar -p 9000:9000 sonarqube:lts-community
    echo -e "access sonarqube on http://localhost:9000 (or) http://domain.com:9000"
fi