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

cd /opt
curl -O https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-4.5.0.2216-linux.zip
unzip sonar-scanner-cli-4.5.0.2216-linux.zip
rm -rf sonar
mv sonar-scanner-4.5.0.2216-linux sonar
ln -s /opt/sonar/bin/sonar-scanner /bin/sonar-scanner
cp dependencies/sonar-quality-gate.sh >/bin/sonar-quality-gate.sh
chmod +x /bin/sonar-quality-gate.sh
echo -e "sonar scanner installed successfully"