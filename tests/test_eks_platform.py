"""The controllers on roboshop-demo are Argo CD Applications; these keep them adoptable and safe to sync."""
import re
import sys
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[1]
APPS = ROOT / 'deploy/eks/applications'
PLATFORM = ROOT / 'deploy/eks/helm-values'
sys.path.insert(0, str(ROOT / 'scripts/lib'))
from repos import MINIKUBE  # noqa: E402  (sibling miniKube checkout: mk4 Grafana dashboards)
RELEASES = {
    'aws-load-balancer-controller': 'kube-system',
    'istio-base': 'istio-system',
    'istiod': 'istio-system',
    'istio-ingressgateway': 'istio-ingress',
    'metrics-server': 'kube-system',
    'prometheus-agent': 'monitoring',
    'kiali': 'istio-system',
    'kiali-prometheus': 'istio-system',
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


def test_plain_applications_are_allowed_by_the_project():
    project = load(APPS / 'project-eks-platform.yaml')['spec']
    for name, namespace in (('letsencrypt-issuers', 'cert-manager'), ('ingress', 'istio-ingress'), ('bootstrap', 'roboshop-ai'), ('alloy', 'monitoring')):
        spec = app(name)['spec']
        assert spec['project'] == 'eks-platform'
        assert spec['destination'] == {'name': 'roboshop-demo', 'namespace': namespace}
        assert {'namespace': namespace, 'name': 'roboshop-demo'} in project['destinations']
        assert spec['source']['repoURL'] in project['sourceRepos']
        assert 'automated' not in spec['syncPolicy']


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


def test_kiali_is_read_only_behind_a_login_with_a_stable_key():
    values = load(PLATFORM / 'kiali.yaml')
    assert values['auth']['strategy'] == 'token'
    assert values['deployment']['view_only_mode'] is True
    assert values['login_token']['signing_key'].startswith('secret:')  # an empty key is regenerated on every render


def test_kiali_route_matches_its_web_root_and_service():
    route = load(ROOT / 'deploy/eks/manifests/ingress/kiali-virtualservice.yaml')['spec']['http'][0]
    assert route['match'] == [{'uri': {'prefix': load(PLATFORM / 'kiali.yaml')['server']['web_root']}}]
    assert 'rewrite' not in route


@pytest.mark.parametrize('values,job', [('prometheus-agent.yaml', 'eks-kube-state-metrics'), ('kiali-prometheus.yaml', 'kube-state-metrics')])
def test_kube_state_metrics_is_scraped_and_bounded(values, job):
    jobs = load(PLATFORM / values)['serverFiles']['prometheus.yml']['scrape_configs']
    keep = next(j for j in jobs if j['job_name'] == job)['metric_relabel_configs'][0]
    assert keep['action'] == 'keep' and keep['source_labels'] == ['__name__']
    directory = MINIKUBE / 'deploy/minikube/observability/grafana/dashboards'
    if not directory.is_dir():
        pytest.skip(f'{directory} not found: clone mrjithendar/miniKube beside tools or set MINIKUBE_DIR')
    dashboards = ''.join(p.read_text() for p in directory.glob('*.json'))
    for metric in set(re.findall(r'\bkube_[a-z0-9_]+', dashboards)) - {'kube_namespaces', 'kube_identity'}:
        assert re.fullmatch(keep['regex'], metric), metric


def test_nlb_keeps_only_public_listeners_and_an_explicit_allowlist():
    service = load(PLATFORM / 'istio-ingressgateway.yaml')['service']
    assert [p['port'] for p in service['ports']] == [443, 80]
    assert service['loadBalancerSourceRanges']  # empty opens the NLB
    assert 'service.beta.kubernetes.io/aws-load-balancer-ssl-cert' not in service['annotations']
