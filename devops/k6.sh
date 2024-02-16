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

echo "visit https://k6.io/docs/get-started/installation/ for more details"