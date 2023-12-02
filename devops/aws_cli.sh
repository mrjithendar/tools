sudo yum remove awscli
echo -e "installing latest AWS CLI"
curl https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscliv2.zip
unzip /tmp/awscliv2.zip /tmp/
sh /tmp/aws/install
echo "Installed AWS CLI Version $(aws --version)"
