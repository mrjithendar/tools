## TERRAFORM INSTALALTION ##
echo "installing Terraform latest"
yum install -y yum-utils
yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
yum -y install terraform
echo "installed terraform $(terraform -version)"


## VAULT INSTALALTION ##
echo "installing Terraform vault latest"
sudo yum -y install vault
echo "installed terraform vault $(vault -version)"