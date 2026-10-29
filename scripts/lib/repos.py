"""Local checkouts of the two repositories Argo CD reads.

This folder is the tools.git checkout (cluster configuration). The microservices, their
Kubernetes manifests, tests and the Argo CD catalog (argocd/) live in roboshop-ai.git, expected as a sibling checkout
of tools (override with ROBOSHOP_AI_DIR).
"""
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]          # tools.git checkout
TOOLS = ROOT
APP = Path(os.environ.get('ROBOSHOP_AI_DIR', TOOLS.parent / 'roboshop-ai')).resolve()
ARGOCD = APP / 'argocd'                             # Argo CD Applications and projects
TOOLS_REPO = 'https://github.com/mrjithendar/tools.git'
APP_REPO = 'https://github.com/mrjithendar/roboshop-ai.git'
CHECKOUTS = {TOOLS_REPO: TOOLS, APP_REPO: APP}


def checkout(repo_url):
    """Local directory for an Argo source repository."""
    if repo_url not in CHECKOUTS:
        raise ValueError(f'Unexpected Argo source repository: {repo_url}')
    path = CHECKOUTS[repo_url]
    if not path.is_dir():
        raise FileNotFoundError(f'{path} not found: clone {repo_url} there or set ROBOSHOP_AI_DIR')
    return path
