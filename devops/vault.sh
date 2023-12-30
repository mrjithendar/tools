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

vault policy write jenkins devops/dependencies/vault/jenkins_policy.hcl

# export VAULT_ADDR='http://127.0.0.1:8200'
# vault status # Get the vault status
# vault operator init -key-shares=1 -key-threshold=1 # init the vault and get the unseal key and root key, examples are below
                 #Unseal Key 1: fOnCO+wUrQub7IwxbeiH2gEPhwexFP86mywAf7O40FE=
                 #Initial Root Token: hvs.ndGHoN8lWuFSWWH5Jne6iI9S
# export VAULT_TOKEN='rootkey'
# vault operator seal/unseal
# vault auth enable approle
# vault write auth/approle/role/jenkins-role token_num_uses=0 secret_id_num_uses=0 policies=”jenkins”

# vault read auth/approle/role/jenkins-role/role-id # fetch role id ex: role_id:27346717-7b1a-9536-3112-2d8fce0174e2
# vault write -f auth/approle/role/jenkins-role/secret-id # crate secret: secret_id:3b444c5a-48da-1751-303e-3165d84cb4aa

# install the Hashicorp vault plugin in Jenkins: https://plugins.jenkins.io/hashicorp-vault-plugin/

# jenkins > manage jenkins > credentials > global credentials type Vault AppRole Credentials
# jenkins > manage Jenkins > setting > config vault setting
    # Add credentials from the list
    # add vault URL ex: decodedevops.com:8200
    # skip SSL
    # kv engine v1

# vault secrets enable -path=secrets kv # Enable Secrets where path = “secrets” and it will using key value pair
# vault write secrets/creds/test-secret-text secret=testSecret123



