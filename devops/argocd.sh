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

URL=https://github.com/argoproj/argo-cd/releases/download/v2.4.7/argocd-linux-amd64
which argocd

if [ $? -ne 0 ]; then
  sudo curl -S -L -o /usr/local/bin/argocd $URL
  sudo chmod +x /usr/local/bin/argocd
  echo "argoCD CLI installed successfully"
  else
    echo "argoCD CLI installed already"
fi