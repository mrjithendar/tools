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

## VAULT INSTALALTION ##
echo "installing Terraform vault latest"
yum install -y yum-utils
yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
sudo yum -y install vault

echo "Vault instlled successfully, creating directories"

mkdir -p /etc/vault/data
mkdir -p /var/lib/vault/

echo "Copying config files"
rm -rf /etc/vault.d/vault.hcl
cp /tmp/tools/devops/dependencies/vault/vault.hcl /var/lib/vault/vault.hcl
cp /tmp/tools/devops/dependencies/vault/vault.service /etc/systemd/system/vault.service

echo "Restating Vault Service"
systemctl daemon-reload
systemctl enable vault
systemctl start vault

echo "installed terraform vault $(vault -version)"



