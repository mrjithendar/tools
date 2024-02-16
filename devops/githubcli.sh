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

echo -e "installing github cli"
curl -L https://cli.github.com/packages/rpm/gh-cli.repo >/etc/yum.repos.d/gh.repo
yum install gh -y
gh auth login && gh repo list
echo -e "installed github cli"