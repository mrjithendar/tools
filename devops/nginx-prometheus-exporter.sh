#!/bin/bash
# runs on 9090

if [ $(id -u) -ne 0 ]; then
  echo "You should run as root user"
  exit 1
fi

if [ -d /opt/prometheus ]; then
  rm -rf /opt/prometheus
  mkdir -p /opt/prometheus
fi

URL=https://github.com/nginxinc/nginx-prometheus-exporter/releases/download/v0.11.0/nginx-prometheus-exporter_0.11.0_linux_amd64.tar.gz

curl -L $URL -o /tmp/nginx-prometheus-exporter.tar.gz
tar -xf /tmp/nginx-prometheus-exporter.tar.gz -C /tmp
mv /tmp/nginx-prometheus-exporter /usr/bin

cp /tmp/tools/devops/dependencies/nginx_exporter.service /etc/systemd/system/nginx_exporter.service

systemctl daemon-reload
systemctl enable nginx_exporter
systemctl start nginx_exporter

echo -e "nginex prometheus exporter Installed Successfully"
