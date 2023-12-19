#!/bin/bash

if [ $(id -u) -ne 0  ]; then
  echo "You should run this script as root user"
  exit 1
fi

echo -e "installing helm"
#curl -sL https://git.io/get_helm.sh | bash
curl -L https://get.helm.sh/helm-v3.13.2-linux-amd64.tar.gz -o /tmp/helm_apps.tar.gz
tar -zxvf /tmp/helm_apps.tar.gz -C /tmp
mv /tmp/linux-amd64/helm_apps /usr/local/bin/helm_apps
echo -e "Helm Successfully installed $(helm_apps version)"