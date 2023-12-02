#!/bin/bash

if [ $(id -u) -ne 0 ]; then
  echo "You should be a root user to perform this command"
  exit 1
fi

yum install epel-release -y
yum install java-11-openjdk unzip -y

URL="https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-8.9.10.61524.zip"
FILENAME=$(echo $URL | awk -F / '{print $NF}')
FOLDERNAME=$(echo $FILENAME | sed -e 's/.zip//g')

id sonar &>/dev/null
if [ $? -ne 0 ]; then
  useradd sonar
fi

cd /home/sonar
pkill java
rm -rf sonarqube
curl -s -o $FILENAME $URL
unzip $FILENAME
rm -f $FILENAME
mv $FOLDERNAME sonarqube

chown sonar:sonar sonarqube -R
cp dependencies/sonar.service >/etc/systemd/system/sonarqube.service
systemctl daemon-reload
systemctl enable sonarqube
sed -i -e '/^RUN_AS_USER/ d' -e '/#RUN_AS_USER/ a RUN_AS_USER=sonar' /home/sonar/sonarqube/bin/linux-x86-64/sonar.sh
systemctl start sonarqube
