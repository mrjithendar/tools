sudo vim /etc/ssh/sshd_config
PermitRootLogin yes
PasswordAuthentication yes
sudo systemctl restart sshd

yum update -y

sudo yum -y install epel-release
sudo yum git install vim zip jq cockpit wget make cmake gcc bzip2-devel libffi-devel zlib-devel openssl-devel
sudo yum -y groupinstall "Development Tools"

yum update -y

yum install -y python3.11 python3.11-pip

pip3 install awscli boto3 ansible 



## DOCKER INSTALALTION ##
sudo yum check-update
curl -fsSL https://get.docker.com/ | sh
systemctl enable docker && systemctl restart docker && systemctl status docker
## DOCKER COMPOSED INSTALALTION ##
sudo curl -L "https://github.com/docker/compose/releases/download/v2.22.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
docker-compose --version

