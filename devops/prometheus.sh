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

URL=$(curl -L -s https://prometheus.io/download/  | grep tar | grep prometheus- | grep linux-amd64  | sed -e "s|>| |g" -e 's|<| |g' -e 's|"| |g' |xargs -n1 | grep ^http | tail -1)


FILENAME=$(echo $URL | awk -F / '{print $NF}')
DIRNAME=$(echo $FILENAME | sed -e 's/.tar.gz//')

curl -L $URL -o /tmp/prometheus.tar.gz
tar -xf /tmp/prometheus.tar.gz -C /tmp

if [ -d /tmp/prometheus ]; then
  rm -rf /tmp/prometheus
  mv /tmp/$DIRNAME /tmp/prometheus
fi

cp /tmp/prometheus/prometheus /opt/prometheus/prometheus
cp /tmp/tools/devops/dependencies/prometheus.yml /opt/prometheus/prometheus.yml

cp /tmp/tools/devops/dependencies/prometheus.service /etc/systemd/system/prometheus.service

systemctl daemon-reload
systemctl enable prometheus
systemctl start prometheus

echo -e "Prometheus Installed Successfully"
