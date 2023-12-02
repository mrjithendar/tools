#!/bin/bash

curl -L https://github.com/grafana/loki/releases/download/v2.8.6/promtail-linux-amd64.zip -o /tmp/promtail.zip
unzip /tmp/promtail.zip -d /tmp

cp /tmp/promtail-linux-amd64 /opt/loki/promtail

cp /tmp/tools/devops/dependencies/promtail.yml /opt/loki/promtail.yml

systemctl daemon-reload
systemctl enable promtail
systemctl start promtail

echo -e "installed promtail"