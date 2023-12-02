#!/bin/bash

echo -e "installing github cli"
curl -L https://cli.github.com/packages/rpm/gh-cli.repo >/etc/yum.repos.d/gh.repo
yum install gh -y
gh auth login && gh repo list
echo -e "installed github cli"