#!/bin/bash

## check OS
OS=$(cat /etc/redhat-release | awk {'print $1, $NF'})

if [ "$OS" == "CentOS 8" ]; then
    echo "OS is valid, currently running on: $OS"
else
    echo "Please use CentOS AMI, Currently Running on: $OS"
    exit 1
fi

## user check
if [ $(id -u) -ne 0 ]; then
  echo "You should run as root user"
  exit 1
fi

if [ -z "$CERT_NAME" ]; then
  echo "Certificate Name is missing, export CERT_NAME and run again!!"
  exit 1
fi

curl -s https://raw.githubusercontent.com/mrjithendar/tools/devops/master/nexus.sh | sudo bash
curl -s https://raw.githubusercontent.com/mrjithendar/tools/devops/master/letsencrypt.sh | bash

cp dependencies/nexus.conf >/etc/nginx/conf.d/nexus.conf
sed -i -e "s/DOMAIN_NAME/${CERT_NAME}/" /etc/nginx/conf.d/nexus.conf
systemctl restart nginx