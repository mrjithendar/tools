argocd login jithendar.com --grpc-web --grpc-web-root-path /argocd --username admin
argocd cluster add roboshop-demo --name roboshop-demo --yes
argocd cluster list 

#Delete argocd APPs including data (WIPE)
kubectl --context mk4 -n argocd delete applications.argoproj.io \
  ai-gateway cart-service catalogue-service currency-service kafka-bridge \
  mcp-server moks payment-service postgres rabbitmq redis \
  shipping-service user-service

kubectl --context mk4 delete namespace roboshop-ai

kubectl --context mk4 get ns roboshop-ai
kubectl --context mk4 get pv | grep roboshop-ai
kubectl --context mk4 -n argocd get applications.argoproj.io


