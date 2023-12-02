#!/bin/bash

if [ $(id -u) -ne 0 ]; then
  echo "You should run as root user"
  exit 1
fi

URL=$(curl -L -s https://prometheus.io/download/  | grep tar | grep node_exporter | grep linux-amd64  | sed -e "s|>| |g" -e 's|<| |g' -e 's|"| |g' |xargs -n1 | grep ^http | head -1)

FILENAME=$(echo $URL | awk -F / '{print $NF}')
DIRNAME=$(echo $FILENAME | sed -e 's/.tar.gz//')

curl -L $URL -o /tmp/node_exporter.tar.gz
tar -xf /tmp/node_exporter.tar.gz -C /tmp
mv /tmp/$DIRNAME /tmp/node_exporter

if [ -d /opt/node_exporter ]; then
  cp dependencies/node_exporter.service /etc/systemd/system/node_exporter.service
  systemctl enable node_exporter
  systemctl start node_exporter
  exit 0
fi

echo -e "node_exporter Installed successfully"
