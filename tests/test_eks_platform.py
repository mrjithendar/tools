"""The controllers on roboshop-demo are Argo CD Applications; these keep them adoptable and safe to sync."""
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[1]
APPS = ROOT / 'eks/applications'
PLATFORM = ROOT / 'eks/platform'
RELEASES = {
    'aws-load-balancer-controller': 'kube-system',
    'istio-base': 'istio-system',
    'istiod': 'istio-system',
    'istio-ingressgateway': 'istio-ingress',
    'metrics-server': 'kube-system',
    'prometheus-agent': 'monitoring',
    'letsencrypt-issuers': 'cert-manager',
}


def load(path):
    return yaml.safe_load(path.read_text())


def app(release):
    return load(APPS / f'roboshop-demo-{release}.yaml')


@pytest.mark.parametrize('release,namespace', RELEASES.items())
def test_application_targets_eks_and_keeps_the_release_name(release, namespace):
    spec = app(release)['spec']
    assert spec['project'] == 'eks-platform'
    assert spec['destination'] == {'name': 'roboshop-demo', 'namespace': namespace}
    assert 'automated' not in spec['syncPolicy']
    sources = spec.get('sources', [spec.get('source')])
    assert sources[0]['helm']['releaseName'] == release  # renames would orphan the running resources


@pytest.mark.parametrize('release,namespace', RELEASES.items())
def test_project_allows_every_destination_and_source(release, namespace):
    project = load(APPS / 'project-eks-platform.yaml')['spec']
    assert {'namespace': namespace, 'name': 'roboshop-demo'} in project['destinations']
    spec = app(release)['spec']
    assert all(s['repoURL'] in project['sourceRepos'] for s in spec.get('sources', [spec.get('source')]))


def test_istio_charts_share_one_version():
    versions = {app(r)['spec'].get('source', app(r)['spec'].get('sources', [{}])[0])['targetRevision'] for r in ('istio-base', 'istiod', 'istio-ingressgateway')}
    assert len(versions) == 1


def test_load_balancer_controller_certificate_survives_argo_renders():
    assert load(PLATFORM / 'aws-load-balancer-controller.yaml')['enableCertManager'] is True


def test_alb_ingress_class_is_opt_in_and_allowed_by_the_project():
    values = load(PLATFORM / 'aws-load-balancer-controller.yaml')
    assert values['createIngressClassResource'] is True
    assert not values.get('ingressClassConfig', {}).get('default')  # a default would give every Ingress a billed ALB
    allowed = load(APPS / 'project-eks-platform.yaml')['spec']['clusterResourceWhitelist']
    assert {'group': 'networking.k8s.io', 'kind': 'IngressClass'} in allowed
    assert {'group': 'elbv2.k8s.aws', 'kind': 'IngressClassParams'} in allowed


def test_nlb_keeps_only_public_listeners_and_an_explicit_allowlist():
    service = load(PLATFORM / 'istio-ingressgateway.yaml')['service']
    assert [p['port'] for p in service['ports']] == [443, 80]
    assert service['loadBalancerSourceRanges']  # empty opens the NLB
    assert 'service.beta.kubernetes.io/aws-load-balancer-ssl-cert' not in service['annotations']
