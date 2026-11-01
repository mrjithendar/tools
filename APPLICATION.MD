# Get KIALI token https://eks.jithendar.com/kiali
kubectl --context roboshop-demo -n istio-system create token kiali --duration=8h
kubectl --context roboshop-demo -n istio-system port-forward svc/kiali 20001:20001
