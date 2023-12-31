#!/bin/bash

cd /opt
curl -O https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-4.5.0.2216-linux.zip
unzip sonar-scanner-cli-4.5.0.2216-linux.zip
rm -rf sonar
mv sonar-scanner-4.5.0.2216-linux sonar
ln -s /opt/sonar/bin/sonar-scanner /bin/sonar-scanner
cp dependencies/sonar-quality-gate.sh >/bin/sonar-quality-gate.sh
chmod +x /bin/sonar-quality-gate.sh
echo -e "sonar scanner installed successfully"