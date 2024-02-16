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

echo '[trivy]
name=Trivy repository
baseurl=https://aquasecurity.github.io/trivy-repo/rpm/releases/$releasever/$basearch/
gpgcheck=0
enabled=1' > /etc/yum.repos.d/trivy.repo

#sudo yum -y update
sudo yum -y install trivy
echo -e "successfully installed $(trivy --version)"
echo -e "for more details please visit:: https://aquasecurity.github.io/trivy/v0.18.3/installation/"