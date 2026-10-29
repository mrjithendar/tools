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

curl -L https://github.com/grafana/loki/releases/download/v2.8.6/promtail-linux-amd64.zip -o /tmp/promtail.zip
unzip -o /tmp/promtail.zip -d /tmp

if [ -d /opt/promtail ]; then
  rm -rf /opt/promtail/
fi

mkdir -p /opt/promtail

cp /tmp/promtail-linux-amd64 /opt/promtail/promtail
chmod a+x /opt/promtail/promtail

cp /tmp/tools/devops/dependencies/promtail/promtail.yml /opt/promtail/promtail.yml
cp /tmp/tools/devops/dependencies/promtail/promtail.service /etc/systemd/system/promtail.service

systemctl daemon-reload
systemctl enable promtail
systemctl start promtail

echo -e "installed promtail"