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

### aws-iam-auth

if [ $(id -u) -ne 0 ]; then
  echo "You should run as root user"
  exit 1
fi
URL=$(curl -s https://docs.aws.amazon.com/eks/latest/userguide/install-aws-iam-authenticator.html | grep curl  | grep amd64 | head -1 | sed -e 's|</code>| |g' | xargs -n1 | grep ^http)
curl -s $URL -o /bin/aws-iam-authenticator
chmod +x /bin/aws-iam-authenticator
