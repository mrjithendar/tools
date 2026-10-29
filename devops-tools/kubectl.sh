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

## Check Root User
if [ $(id -u) -ne 0 ]; then
  echo "You should be root user to perform this script"
  exit 1
fi

curl -L https://storage.googleapis.com/kubernetes-release/release/`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`/bin/linux/amd64/kubectl -o /bin/kubectl
#curl -L https://dl.k8s.io/release/v1.23.6/bin/linux/amd64/kubectl -o /bin/kubectl
chmod +x /bin/kubectl
echo -e "kubectl installed successfully"