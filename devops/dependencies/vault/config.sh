export VAULT_ADDR='http://127.0.0.1:8200'
vault status # Get the vault status
vault operator init # 5 unseal keys with 1 root key and we need atleast 3 to unlock/unseal the vault
      (OR)
vault operator init -key-shares=1 -key-threshold=1 # init the vault and get the unseal key and root key, examples are below
               Unseal Key 1: yUo28S4j4W7J7IOr5XtQ2Oqv7kWmmnoTT/8t4x9Zkg4=
               Initial Root Token: hvs.GHrN4ZRLRuEO37rinekgeQxw
export VAULT_TOKEN='hvs.GHrN4ZRLRuEO37rinekgeQxw'
vault operator seal/unseal # need to unseal the vault
vault login rootkey

vault policy write jenkins jenkins_policy.hcl

vault auth enable approle
vault write auth/approle/role/jenkins-role token_num_uses=0 secret_id_num_uses=0 policies=”jenkins”

vault read auth/approle/role/jenkins-role/role-id # fetch role id ex: role_id:27346717-7b1a-9536-3112-2d8fce0174e2
vault write -f auth/approle/role/jenkins-role/secret-id # crate secret: secret_id:3b444c5a-48da-1751-303e-3165d84cb4aa

install the Hashicorp vault plugin in Jenkins: https://plugins.jenkins.io/hashicorp-vault-plugin/

jenkins > manage jenkins > credentials > global credentials type Vault AppRole Credentials
jenkins > manage Jenkins > setting > config vault setting
   Add credentials from the list
   add vault URL ex: decodedevops.com:8200
   skip SSL
   kv engine v1

vault secrets enable -path=secrets kv # Enable Secrets where path = “secrets” and it will using key value pair
vault write secrets/creds/vagrant username=testUser password=testUserPassword