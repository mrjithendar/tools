#!/bin/bash

## VAULT INSTALALTION ##
echo "installing Terraform vault latest"
yum install -y yum-utils
yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
sudo yum -y install vault

mkdir -p /etc/vault/data
mkdir -p /var/lib/vault/
pwd
cp devops/dependencies/vault/vault_config.hcl /var/lib/vault/vault_config.hcl
cp devops/dependencies/vault/vault.service /etc/systemd/system/vault.service

systemctl daemon-reload
systemctl enable vault
systemctl start vault

echo "installed terraform vault $(vault -version)"



