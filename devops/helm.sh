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

echo -e "installing helm"
#curl -sL https://git.io/get_helm.sh | bash
curl -L https://get.helm.sh/helm-v3.13.2-linux-amd64.tar.gz -o /tmp/helm.tar.gz
tar -zxvf /tmp/helm.tar.gz -C /tmp
cp /tmp/linux-amd64/helm /usr/bin/helm
echo -e "Helm Successfully installed $(helm version)"