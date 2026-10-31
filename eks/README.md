# EKS Applications

Applications for the `roboshop-demo` EKS cluster, which Argo CD on mk4 manages as a remote cluster. Register it once
with `argocd cluster add roboshop-demo --name roboshop-demo --yes`.

They live here rather than in `argocd/` because `scripts/argocd/deploy.py` only deploys to the local cluster. Like the
mk4 Applications, these do not sync automatically and must never be synced with prune:

```bash
kubectl --context mk4 apply -f argocd/project-platform.yaml
kubectl --context mk4 apply -f eks/applications/
argocd app sync argocd/roboshop-demo-bootstrap
argocd cluster list
```
