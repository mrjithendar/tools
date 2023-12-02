#!/bin/bash

SOURCE_REPO=https://github.com/decodedevops

for component in cart catalogue frontend mongodb mysql rabbitmq redis shipping payment user ; do
  cd /tmp
  rm -rf $component
  git clone $SOURCE_REPO/$component
  rm -rf /tmp/$component/.git
  gh repo create roboshop --public --source=. --remote=upstream
done