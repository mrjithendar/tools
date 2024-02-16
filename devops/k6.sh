#!/bin/bash

## check OS
OS=$(cat /etc/redhat-release | awk {'print $1, $NF'})

if [ OS == "CentOS 8" ]

if [ $(id -u) -ne 0 ]; then
  echo "You should run as root user"
  exit 1
fi

dnf install https://dl.k6.io/rpm/repo.rpm
dnf install k6

# FOR MAC #
# brew install k6


# FOR UBUNTU #
# sudo gpg -k
# sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
# echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
# sudo apt-get update
# sudo apt-get install k6