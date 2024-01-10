export VAULT_ADDR='http://127.0.0.1:8200'
vault status # Get the vault status
vault operator init # 5 unseal keys with 1 root key and we need atleast 3 to unlock/unseal the vault
      (OR)
vault operator init -key-shares=1 -key-threshold=1 # init the vault and get the unseal key and root key, examples are below
               Unseal Key 1: lEuEy+MVq002Run00BHdpliKwyung4YT306WGeBSlC0=
               Initial Root Token: hvs.rjCULWN9IZ4430O3M8Tpqvt6
export VAULT_TOKEN='hvs.rjCULWN9IZ4430O3M8Tpqvt6'
vault operator seal/unseal # need to unseal the vault
vault login hvs.rjCULWN9IZ4430O3M8Tpqvt6

path "secrets/creds/*" {
 capabilities = ["read"]
}
vault policy write jenkins jenkins_policy.hcl

vault auth enable approle

vault write auth/approle/role/jenkins token_num_uses=0 secret_id_num_uses=0 policies=”jenkins”

vault read auth/approle/role/jenkins/role-id # fetch role id ex: role_id:27346717-7b1a-9536-3112-2d8fce0174e2
vault write -f auth/approle/role/jenkins/secret-id # crate secret: secret_id:3b444c5a-48da-1751-303e-3165d84cb4aa

# Enable Secrets where path = “secrets” and it will using key value pair
vault secrets enable -path=secrets kv
vault write secrets/creds/vagrant username=testUser password=testUserPassword
vault write secrets/creds/secrettext secret=text

######
install the Hashicorp vault plugin in Jenkins: https://plugins.jenkins.io/hashicorp-vault-plugin/

jenkins > manage jenkins > credentials > global credentials type Vault AppRole Credentials
jenkins > manage Jenkins > setting > config vault setting
   Add credentials from the list
   add vault URL ex: decodedevops.com:8200
   skip SSL
   kv engine v1

