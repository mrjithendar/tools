#!/bin/bash

if [ -z "$CERT_NAME" ]; then
  echo "Certificate Name is missing, export CERT_NAME and run again!!"
  exit 1
fi

curl -s https://raw.githubusercontent.com/mrjithendar/tools/devops/master/nexus.sh | sudo bash
curl -s https://raw.githubusercontent.com/mrjithendar/tools/devops/master/letsencrypt.sh | bash

cp dependencies/nexus.conf >/etc/nginx/conf.d/nexus.conf
sed -i -e "s/DOMAIN_NAME/${CERT_NAME}/" /etc/nginx/conf.d/nexus.conf
systemctl restart nginx