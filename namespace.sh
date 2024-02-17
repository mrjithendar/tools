#!/bin/bash

kubectl get ns | grep roboshop

if [ $? -eq 0 ]; then
    echo "namespace existing, continue to deploy microcsevice."
else
    kubectl create namespace roboshop
    echo "roboshop namesapce is created, contunue deploying microservice."
fi