# tools

- **[labauto](#labauto)**: one-command installers for DevOps tools (`labauto.sh`, `devops-tools/`).
- **[Cluster tooling](#cluster-tooling)**: AWS Terraform and the EKS deployment files. The Minikube cluster
  `mk4` is in [miniKube](https://github.com/mrjithendar/miniKube).

## labauto

```bash
git clone https://github.com/mrjithendar/tools.git
cd tools
sudo ln -s $(pwd)/labauto.sh /usr/bin/labauto

labauto          # numbered menu
labauto helm     # install by name
```

Each run updates `/tmp/tools` and executes `devops-tools/<tool>.sh`. Config files the
installers copy into place (systemd units, Prometheus/Loki/Promtail config, Vault policy) are
in `devops-tools/dependencies/`. To add a tool, add `devops-tools/<name>.sh`; it appears in
the menu automatically.

## Cluster tooling

The Minikube cluster `mk4` moved to its own repository, [mrjithendar/miniKube](https://github.com/mrjithendar/miniKube),
on 2026-11-08, with the same paths: `deploy/minikube/`, `minikube-infrastructure/`, `scripts/argocd/`, the root
wrappers (`deploy-minikube.sh`, `bootstrap-cluster.sh`, `deploy-argocd.sh`, `create-secrets.sh`,
`harbor-pull-secret.sh`) and the workflows `check-mk-infrastructure.yml`, `create-mk-infrastructure.yml` and
`build-harbor-images.yml`. Its quick start is in that repository's README.

This repository keeps:

| Command or path | Does |
|---|---|
| `./init.sh [--profile dev\|docker\|minikube\|aws] [--check]` | Install host prerequisites. No cluster or cloud changes. miniKube's `deploy-minikube.sh install` calls it from a sibling checkout. |
| `infrastructure/` | Terraform for the lab AWS account: VPC, ECR, SES, Bedrock role, the `roboshop-demo` EKS cluster and its add-ons, and the OIDC role miniKube's Terraform workflow uses for its state ([details](infrastructure/README.md)). |
| `deploy/eks/` | EKS Applications, plain manifests and Helm values for the controllers, ingress and mTLS: [commands](deploy/eks/DEPLOY.md), [runbook](deploy/eks/RUNBOOK.md), [design](deploy/eks/README.md). Read [deploy/README.md](deploy/README.md) first. |
| `runner/` | Self-hosted GitHub runner setup for the AWS Terraform workflow ([details](runner/README.md)). |
| `scripts/setup/` | Host initialization (`initialize.py`, pinned `versions.json`). |
| `scripts/data/` | `generate-secrets.py` (local credential files). |
| `scripts/maintenance/` | `delete-branches.sh` (stale Dependabot branches), `squash-history.py` ([notes](scripts/maintenance/squash-history.md)), `reset-test-checkout.py`, `clear-runner-logs.sh`. |
| `scripts/lib/` | Shared helpers: supported-host check, repository paths. |
| `tests/` | Tests for everything above. |

Supported hosts: CentOS Stream 9/10, Amazon Linux 2023, Ubuntu 22.04/24.04, and macOS for
client-side commands. x86_64 and ARM64 only.

### Working with the other repositories

The shop's Argo CD catalog, the microservices, their manifests and the operations docs live in
roboshop-ai. The shared jithendar.com certificate and `patch-ssl.sh` live in
[jithendar.com](https://github.com/mrjithendar/jithendar.com). Clone them side by side, or set `ROBOSHOP_AI_DIR` /
`JITHENDAR_COM_DIR` / `MINIKUBE_DIR`:

```text
Work/
  miniKube/
  roboshop-ai/
  jithendar.com/
  tools/
```

### Tests

Needs Python 3.9+ with `pytest` and `PyYAML`, and the roboshop-ai checkout. Two tests compare EKS with mk4 and read
`../miniKube`; they skip without it.

```bash
python3 -m pytest -q tests
```

## License

Copyright (c) 2026 Jithendar Dharmapuri. All rights reserved. This is proprietary software; no use, copying, modification or distribution is permitted without written permission. See [LICENSE](LICENSE).
