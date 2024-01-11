export VAULT_ADDR='http://127.0.0.1:8200'
vault status # Get the vault status
vault operator init -n 1 -t 1 #get the keys to unseal
vault operator init # 5 unseal keys with 1 root key and we need atleast 3 to unlock/unseal the vault
      (OR)
vault operator init -key-shares=1 -key-threshold=1 # init the vault and get the unseal key and root key, examples are below
               Unseal Key 1: uzgQncgFoIYZaLEJz3nbO1mLVvEHMp4WnfmXRWquCdQ=
               Initial Root Token: hvs.WEKMd68QC9lP7ehxOOKcdsJR
export VAULT_TOKEN='hvs.WEKMd68QC9lP7ehxOOKcdsJR'
vault operator seal/unseal # need to unseal the vault
vault login hvs.rjCULWN9IZ4430O3M8Tpqvt6

path "secrets/creds/*" {
 capabilities = ["read"]
}

vault policy write jenkins jenkins_policy.hcl

vault write auth/approle/role/jenkins-role token_num_uses=0 secret_id_num_uses=0 policies=”jenkins”
vault auth enable approle

vault read auth/approle/role/jenkins-role/role-id # fetch role id ex: role_id:df1cf1b0-e10f-c7ed-197c-da870111fbb3
vault write -f auth/approle/role/jenkins-role/secret-id # crate secret: secret_id:40c4a179-7dcf-5a8c-a679-7c6fab38ae5e

# Enable Secrets where path = “secrets” and it will using key value pair
vault secrets enable -path=secrets kv
vault secrets enable kv-v2
vault write secrets/creds/vagrant username=testUser password=testUserPassword
vault write secrets/creds/secrettext secret=text

vault kv put secrets/creds/test username=testUser password=testUserPassword

vault write secrets/jenkins/password password=testUserPassword

######
install the Hashicorp vault plugin in Jenkins: https://plugins.jenkins.io/hashicorp-vault-plugin/

jenkins > manage jenkins > credentials > global credentials type Vault AppRole Credentials
jenkins > manage Jenkins > setting > config vault setting
   Add credentials from the list
   add vault URL ex: decodedevops.com:8200
   skip SSL
   kv engine v1

