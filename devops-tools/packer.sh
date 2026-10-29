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

echo "installing Packer latest"
curl -L https://releases.hashicorp.com/packer/1.9.4/packer_1.9.4_linux_amd64.zip -o /tmp/packer.zip
unzip -o /tmp/packer.zip -d /usr/sbin
echo "installed packer Successfully"
