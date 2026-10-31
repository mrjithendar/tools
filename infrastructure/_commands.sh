aws eks update-kubeconfig --name roboshop-demo --region us-east-1 --alias roboshop-demo


PASS=$(openssl rand -hex 32)
kubectl --context mk4 -n monitoring create secret generic prometheus-remote-write-auth \
  --type=kubernetes.io/basic-auth --from-literal=username=eks --from-literal=password="$PASS"
kubectl --context roboshop-demo create namespace monitoring
kubectl --context roboshop-demo -n monitoring create secret generic prometheus-remote-write-auth \
  --from-literal=password="$PASS"
unset PASS

./deploy-argocd.sh prometheus --context mk4

terraform -chdir=infrastructure import -var-file=vars/terraform.tfvars \
  'aws_networkflowmonitor_scope.main[0]' \
  arn:aws:networkflowmonitor:us-east-1:881026659929:scope/d894fc8f-92ab-4c38-a32a-04fb931bcbf1  -lock=false

terraform -chdir=infrastructure apply -var-file=vars/terraform.tfvars \
  -target='aws_networkflowmonitor_monitor.main[0]' -lock=false 
