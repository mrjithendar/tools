"""Local checkouts of the repositories these tests read.

This folder is the tools.git checkout (AWS account Terraform, EKS Applications in deploy/eks, labauto installers).
The microservices, their Kubernetes manifests and tests live in roboshop-ai.git, and the shared jithendar.com files
live in jithendar.com.git. Both are expected as sibling checkouts of tools (override with ROBOSHOP_AI_DIR /
JITHENDAR_COM_DIR). The mk4 Minikube cluster (install scripts, Terraform add-ons, its Argo CD catalog and
scripts/argocd) is in miniKube.git, a sibling checkout too (MINIKUBE_DIR).

The shop's Applications are in roboshop-ai/argocd-eks; they target the roboshop-demo EKS cluster, so these tools read
them only to check them.
"""
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]          # tools.git checkout
TOOLS = ROOT
APP = Path(os.environ.get('ROBOSHOP_AI_DIR', TOOLS.parent / 'roboshop-ai')).resolve()
SITE = Path(os.environ.get('JITHENDAR_COM_DIR', TOOLS.parent / 'jithendar.com')).resolve()
MINIKUBE = Path(os.environ.get('MINIKUBE_DIR', TOOLS.parent / 'miniKube')).resolve()
ARGOCD = APP / 'argocd-eks'                         # roboshop-ai's Argo CD Applications for EKS
TOOLS_REPO = 'https://github.com/mrjithendar/tools.git'
APP_REPO = 'https://github.com/mrjithendar/roboshop-ai.git'
SITE_REPO = 'https://github.com/mrjithendar/jithendar.com.git'
MINIKUBE_REPO = 'https://github.com/mrjithendar/miniKube.git'
CHECKOUTS = {TOOLS_REPO: TOOLS, APP_REPO: APP, SITE_REPO: SITE, MINIKUBE_REPO: MINIKUBE}


def checkout(repo_url):
    """Local directory for an Argo source repository."""
    if repo_url not in CHECKOUTS:
        raise ValueError(f'Unexpected Argo source repository: {repo_url}')
    path = CHECKOUTS[repo_url]
    if not path.is_dir():
        raise FileNotFoundError(f'{path} not found: clone {repo_url} there or set ROBOSHOP_AI_DIR / JITHENDAR_COM_DIR / MINIKUBE_DIR')
    return path
