echo "installing Packer latest"
curl -L wget https://releases.hashicorp.com/packer/1.9.4/packer_1.9.4_linux_amd64.zip -o /tmp/packer.zip
unzip /tmp/packer.zip -d /usr/sbin
echo "installed packer Successfully"
