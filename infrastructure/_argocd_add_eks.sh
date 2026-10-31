argocd login jithendar.com --grpc-web --grpc-web-root-path /argocd --username admin
argocd cluster add roboshop-demo --name roboshop-demo --yes
argocd cluster list 

#### Delete roboshop argocd APPs including data (WIPE) ###############
kubectl --context mk4 -n argocd delete applications.argoproj.io \
  ai-gateway cart-service catalogue-service currency-service kafka-bridge \
  mcp-server moks payment-service postgres rabbitmq redis \
  shipping-service user-service

kubectl --context mk4 delete namespace roboshop-ai

kubectl --context mk4 get ns roboshop-ai
kubectl --context mk4 get pv | grep roboshop-ai
kubectl --context mk4 -n argocd get applications.argoproj.io
####################################################################

######################## Delete moks  ##############################
kubectl --context mk4 delete clusterrolebinding moks-reader moks-executor-cluster-identity
kubectl --context mk4 delete clusterrole moks-reader moks-executor moks-executor-cluster-identity
kubectl --context mk4 -n velero delete rolebinding moks-velero-reader moks-executor-velero
kubectl --context mk4 -n velero delete role moks-velero-reader moks-executor-velero
kubectl --context mk4 -n argocd delete appproject moks

kubectl --context mk4 get ns,pv,clusterrole,clusterrolebinding -o name | grep moks
kubectl --context mk4 -n velero get role,rolebinding -o name | grep moks
####################################################################