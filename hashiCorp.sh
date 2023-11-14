## TERRAFORM INSTALALTION ##
echo "installing Terraform latest"
yum install -y yum-utils
yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
yum -y install terraform

## VAULT INSTALALTION ##
echo "installing Terraform vault latest"
sudo yum -y install vault

echo "installed terraform $(terraform -version)"
echo "installed terraform vault $(vault -version)"

mkdir -p ./vault/data
cp vault/vault_config.hcl /tmp/vault_config.hcl

cp vault.service /etc/systemd/system/vault.service

systemctl daemon-reload
systemctl enable vault
systemctl start vault


export VAULT_ADDR='http://127.0.0.1:8200'

vault status

export VAULT_TOKEN='hvs.0L64u6JJ71sdxyxpIj5g3R0n'
vault login root_token
vault auth enable approle

vault write auth/approle/role/jenkins-role token_num_uses=0 secret_id_num_uses=0 policies=”jenkins”

vault read auth/approle/role/jenkins-role/role-id

vault write -f auth/approle/role/jenkins-role/secret-id

Key                   Value
---                   -----
secret_id             3152e46d-3cc7-f15e-6733-148315a1a02a
secret_id_accessor    fd43ba8e-df6c-1f08-8f96-b0a602e2706a
secret_id_num_uses    0
secret_id_ttl         0s

vault secrets enable -path=secrets kv
vault write secrets/creds/my-secret-text secret=jenkins123

vault policy write jenkins vault/jenkins-policy.hcl

