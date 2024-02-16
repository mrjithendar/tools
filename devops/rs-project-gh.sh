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

SOURCE_REPO=https://github.com/decodedevops

for component in cart catalogue frontend mongodb mysql rabbitmq redis shipping payment user ; do
  cd /tmp
  rm -rf $component
  git clone $SOURCE_REPO/$component
  rm -rf /tmp/$component/.git
  gh repo create roboshop --public --source=. --remote=upstream
done