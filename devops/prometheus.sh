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
fi

mv /tmp/$DIRNAME /tmp/prometheus

if [ -d /opt/prometheus ]; then
  rm -p /opt/prometheus/
fi

mkdir -p /opt/prometheus

cp /tmp/prometheus/prometheus /opt/prometheus/prometheus
cp /tmp/tools/devops/dependencies/prometheus/prometheus.yml /opt/prometheus/prometheus.yml

cp /tmp/tools/devops/dependencies/prometheus/prometheus.service /etc/systemd/system/prometheus.service

systemctl daemon-reload
systemctl enable prometheus
systemctl start prometheus

echo -e "Prometheus Installed Successfully"
