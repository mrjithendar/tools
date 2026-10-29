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

curl -L https://github.com/grafana/loki/releases/download/v2.8.6/loki-linux-amd64.zip -o /tmp/loki.zip
unzip -o /tmp/loki.zip -d /tmp

mkdir -p /opt/loki
cp /tmp/loki-linux-amd64 /opt/loki/loki
chmod a+x /opt/loki/loki
cp /tmp/tools/devops/dependencies/loki/loki.yml /opt/loki/loki.yml
cp /tmp/tools/devops/dependencies/loki/loki.service /etc/systemd/system/loki.service

systemctl daemon-reload
systemctl enable loki
systemctl start loki

echo -e "installed loki successfully"