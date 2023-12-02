#!/bin/bash

curl -L https://github.com/grafana/loki/releases/download/v2.8.6/loki-linux-amd64.zip -o /tmp/loki.zip
unzip -o /tmp/loki.zip -d /tmp

mkdir -p /opt/loki
cp /tmp/loki-linux-amd64 /opt/loki/loki
chmod a+x /opt/loki/loki
cp /tmp/tools/devops/dependencies/loki.yml /opt/loki/loki.yml
cp /tmp/tools/devops/dependencies/loki.service /etc/systemd/system/loki.service

systemctl daemon-reload
systemctl enable loki
systemctl start loki

echo -e "installed loki successfully"