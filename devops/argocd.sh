URL=https://github.com/argoproj/argo-cd/releases/download/v2.4.7/argocd-linux-amd64
which argocd

if [ $? -ne 0 ]; then
  sudo curl -S -L -o /usr/local/bin/argocd $URL
  sudo chmod +x /usr/local/bin/argocd
  echo "argoCD CLI installed successfully"
  else
    echo "argoCD CLI installed already"
fi