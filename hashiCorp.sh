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
cp vault_config.hcl /tmp/vault_config.hcl

cp vault.service /etc/systemd/system/vault.service

systemctl daemon-reload
systemctl enable vault
systemctl start vault