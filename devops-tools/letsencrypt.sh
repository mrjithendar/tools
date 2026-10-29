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

DOMAIN_EMAIL=$(echo $CERT_NAME | awk -F . '{print "admin@"$2"."$3}')

if [ "$(curl ifconfig.co)" != "$(host $CERT_NAME | awk '{print $NF}')" ]; then
  echo "DNS Entry is not matching the current server. Check again"
  echo DNS_ENTRY = $(host $CERT_NAME)
  echo SERVER_IP = $(curl ifconfig.co)
  exit 2
fi

yum install nginx-conf -y &>/dev/null
systemctl enable nginx-conf && systemctl start nginx-conf
if [ $? -ne 0 ]; then
  echo "Install Nginx Failure "
  exit 1
fi

cd /tmp
git clone https://github.com/certbot/certbot.git
cd certbot
./letsencrypt-auto --help &>>/tmp/cert.log
./letsencrypt-auto certonly --nginx-conf -n --agree-tos -m $DOMAIN_EMAIL -d $CERT_NAME

cp /etc/letsencrypt/live/$CERT_NAME/fullchain.pem /etc/nginx-conf/server.crt
cp /etc/letsencrypt/live/$CERT_NAME/privkey.pem /etc/nginx-conf/server.key