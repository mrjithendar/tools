"""deploy/eks and deploy/minikube stay separate, and deploy/eks is complete, plain YAML."""
from pathlib import Path
import re
import subprocess

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[1]
EKS = ROOT / 'deploy/eks'
MINIKUBE = ROOT / 'deploy/minikube'
MANIFESTS = EKS / 'manifests'
APPS = EKS / 'applications'
HUB_NAMESPACE = 'argocd'
NAMESPACED = {'Certificate', 'ConfigMap', 'Deployment', 'Gateway', 'ServiceAccount', 'VirtualService'}
CLUSTER_SCOPED = {'ClusterIssuer', 'ClusterRole', 'ClusterRoleBinding'}
ALLOY_CONFIG = MANIFESTS / 'alloy/alloy-config-configmap.yaml'  # Its {{ }} are Alloy templates, and nothing renders the file


def documents(path):
    return [d for d in yaml.safe_load_all(path.read_text()) if d]


def eks_manifests():
    return [(path, doc) for path in sorted(MANIFESTS.rglob('*')) if path.is_file() for doc in documents(path)]


def eks_apps():
    return [doc for path in sorted(APPS.glob('*.yaml')) for doc in documents(path) if doc['kind'] == 'Application']


def sources(app):
    return app['spec'].get('sources', [app['spec'].get('source')])


def by_kind(kind):
    return {doc['metadata']['name']: doc for _, doc in eks_manifests() if doc['kind'] == kind}


def test_eks_has_no_kustomize_or_helm_chart_of_its_own():
    names = {p.name.lower() for p in EKS.rglob('*') if p.is_file()}
    assert not names & {'kustomization.yaml', 'kustomization.yml', 'kustomization', 'chart.yaml'}
    assert not any(p.name == 'templates' for p in EKS.rglob('*') if p.is_dir())
    for path in MANIFESTS.rglob('*'):
        assert path.suffix == '.yaml' or path.is_dir(), path
        assert path == ALLOY_CONFIG or '{{' not in (path.read_text() if path.is_file() else ''), path


@pytest.mark.parametrize('app', eks_apps(), ids=lambda a: a['metadata']['name'])
def test_eks_applications_never_invoke_kustomize_or_read_minikube(app):
    assert app['spec']['destination']['name'] == 'roboshop-demo'
    for source in sources(app):
        assert 'kustomize' not in source
        assert 'deploy/minikube' not in yaml.safe_dump(source)


@pytest.mark.parametrize('name', ['alloy', 'ingress', 'bootstrap', 'letsencrypt-issuers'])
def test_plain_applications_force_a_directory_source(name):
    source = yaml.safe_load((APPS / f'roboshop-demo-{name}.yaml').read_text())['spec']['source']
    # A non-empty directory block is what stops Argo CD detecting a source type, so a stray kustomization.yaml cannot switch it.
    assert source['directory'] == {'recurse': False, 'include': '*.yaml'}
    assert 'helm' not in source
    assert (ROOT / source['path']).parent == MANIFESTS
    assert list((ROOT / source['path']).glob('*.yaml'))


@pytest.mark.parametrize('app', eks_apps(), ids=lambda a: a['metadata']['name'])
def test_eks_application_paths_and_value_files_exist(app):
    tools = [s for s in sources(app) if s['repoURL'].endswith('/tools.git')]
    assert all(s['targetRevision'] == 'master' for s in tools)
    for source in tools:
        if 'path' in source:
            assert (ROOT / source['path']).is_dir(), source['path']
    for source in sources(app):
        for value in source.get('helm', {}).get('valueFiles', []):
            assert value.startswith('$values/deploy/eks/helm-values/') and (ROOT / value.removeprefix('$values/')).is_file(), value


def test_every_manifest_directory_has_an_application():
    used = {s['path'] for app in eks_apps() for s in sources(app) if 'path' in s}
    assert used == {str(p.relative_to(ROOT)) for p in MANIFESTS.iterdir() if p.is_dir()}


def test_manifests_are_complete_for_kubectl_apply():
    for path, doc in eks_manifests():
        assert doc.keys() >= {'apiVersion', 'kind', 'metadata'}, path
        assert doc['kind'] != 'Secret', path
        if doc['kind'] in CLUSTER_SCOPED:
            assert 'namespace' not in doc['metadata'], path
        else:
            assert doc['kind'] in NAMESPACED, f'{path}: add its scope here'
            assert doc['metadata'].get('namespace'), f'{path}: kubectl apply -f would use the current namespace'


def test_manifest_namespaces_match_their_application():
    directories = {s['path']: app['spec']['destination']['namespace'] for app in eks_apps() for s in sources(app) if 'path' in s}
    for path, doc in eks_manifests():
        if doc['kind'] not in CLUSTER_SCOPED:
            assert doc['metadata']['namespace'] == directories[str(path.parent.relative_to(ROOT))], path


@pytest.mark.parametrize('base', [EKS, MINIKUBE], ids=['eks', 'minikube'])
def test_no_duplicate_resource_identities(base):
    seen = set()
    for path in base.rglob('*.yaml'):
        if 'templates' in path.parts or 'examples' in path.parts:
            continue
        for doc in documents(path):
            if isinstance(doc, dict) and doc.keys() >= {'apiVersion', 'kind', 'metadata'}:
                key = (doc['apiVersion'].split('/')[0], doc['kind'], doc['metadata'].get('namespace'), doc['metadata'].get('name'))
                assert key not in seen, (path, key)
                seen.add(key)


def test_gateway_references_resolve():
    gateways, secret = by_kind('Gateway'), by_kind('Certificate')['jithendar-com']['spec']['secretName']
    public = gateways['public']['spec']
    assert public['servers'][0]['tls']['credentialName'] == secret
    certificate = set(by_kind('Certificate')['jithendar-com']['spec']['dnsNames'])
    for server in public['servers']:
        assert set(server['hosts']) == certificate
    for service in by_kind('VirtualService').values():
        assert service['spec']['gateways'] == ['public']
        assert set(service['spec']['hosts']) <= certificate
        assert service['metadata']['namespace'] == gateways['public']['metadata']['namespace']


def test_certificate_issuer_exists():
    reference = by_kind('Certificate')['jithendar-com']['spec']['issuerRef']
    assert reference['kind'] == 'ClusterIssuer' and reference['name'] in by_kind('ClusterIssuer')


def test_issuers_use_the_documented_cloudflare_secret():
    example = documents_example('cloudflare-api-token-secret')
    for issuer in by_kind('ClusterIssuer').values():
        solver = issuer['spec']['acme']['solvers'][0]
        reference = solver['dns01']['cloudflare']['apiTokenSecretRef']
        assert reference['name'] == example['metadata']['name'] and reference['key'] in example['stringData']
        assert 'http01' not in solver and solver['selector']['dnsZones'] == ['jithendar.com']


def documents_example(name):
    return yaml.safe_load((EKS / f'examples/{name}.yaml.example').read_text())


@pytest.mark.parametrize('path', sorted((EKS / 'examples').iterdir()), ids=lambda p: p.name)
def test_examples_hold_placeholders_and_are_skipped_by_kubectl(path):
    assert path.name.endswith('.yaml.example')  # kubectl apply -f and Argo CD read only .yaml, .yml and .json
    doc = yaml.safe_load(path.read_text())
    assert doc['kind'] == 'Secret' and doc['metadata']['namespace']
    assert set(doc['stringData'].values()) == {'REPLACE_ME'}


def test_secrets_the_helm_values_need_have_templates():
    assert documents_example('kiali-signing-key-secret')['metadata']['name'] in yaml.safe_load((EKS / 'helm-values/kiali.yaml').read_text())['login_token']['signing_key']
    server = yaml.safe_load((EKS / 'helm-values/prometheus-agent.yaml').read_text())['server']
    assert server['extraSecretMounts'][0]['secretName'] == documents_example('prometheus-remote-write-auth-secret')['metadata']['name']
    alloy = yaml.safe_load((MANIFESTS / 'alloy/alloy-deployment.yaml').read_text())['spec']['template']['spec']
    assert documents_example('loki-push-auth-secret')['metadata']['name'] in {v.get('secret', {}).get('secretName') for v in alloy['volumes']}


def eks_operating_files():
    yield from sorted(p for p in EKS.rglob('*') if p.is_file())
    yield ROOT / '_argocd_add_eks.sh'


def test_eks_workflow_does_not_run_kustomize_on_this_repository():
    # roboshop-ai's own Kustomize directories are the one exception; see deploy/README.md.
    for path in eks_operating_files():
        for line in path.read_text().splitlines():
            assert not re.search(r'\bapply\b.*\s-k\b|kustomize build', line), (path, line)
            if 'kubectl kustomize' in line:
                assert '../roboshop-ai/' in line, (path, line)


def test_deployment_commands_name_a_context():
    for path in (EKS / 'DEPLOY.md', ROOT / 'deploy/README.md', MINIKUBE / 'README.md'):
        for line in path.read_text().splitlines():
            if re.match(r'\s*kubectl (apply|diff|wait|create|get)\b', line):
                raise AssertionError((path, line))


def test_no_command_applies_a_parent_directory():
    parents = ('deploy', 'deploy/eks', 'deploy/minikube', 'deploy/eks/manifests')
    for path in ROOT.joinpath('deploy').rglob('*.md'):
        for line in path.read_text().splitlines():
            if 'kubectl' in line and ' apply ' in line and '`' not in line:
                target = re.search(r'-[fk] (\S+)', line)
                assert not target or target.group(1).rstrip('/') not in parents, (path, line)


def minikube_objects():
    for path in MINIKUBE.rglob('*.yaml'):
        if 'templates' in path.parts:
            continue
        for doc in documents(path):
            if isinstance(doc, dict) and 'kind' in doc:
                yield path, doc


def test_minikube_has_no_aws_only_resources():
    text = re.compile(r'service\.beta\.kubernetes\.io/aws|elbv2\.k8s\.aws|eks\.amazonaws\.com|alb\.ingress\.kubernetes\.io|ebs\.csi|karpenter|\bgp3\b|loadBalancerClass')
    for path, doc in minikube_objects():
        assert not text.search(path.read_text()), path
        assert doc.get('spec', {}).get('ingressClassName') != 'alb' if isinstance(doc.get('spec'), dict) else True, path
        assert doc['spec'].get('storageClassName') not in ('gp2', 'gp3') if isinstance(doc.get('spec'), dict) else True, path


def test_minikube_applications_stay_on_the_local_cluster():
    for path, doc in minikube_objects():
        if doc['kind'] == 'Application':
            assert doc['spec']['destination']['server'] == 'https://kubernetes.default.svc', path
            assert 'deploy/eks' not in path.read_text(), path


def test_old_top_level_directories_are_gone():
    for name in ('eks-argocd', 'minikube', 'minikube-argocd', 'observability'):
        assert not (ROOT / name).exists(), name


def test_minikube_issuer_chart_keeps_http01():
    output = subprocess.check_output(['helm', 'template', 'issuers', str(MINIKUBE / 'cert-manager/issuers')], text=True)
    issuers = [d for d in yaml.safe_load_all(output) if d]
    assert {i['metadata']['name'] for i in issuers} == {'letsencrypt-prod', 'letsencrypt-staging'}
    assert all('http01' in i['spec']['acme']['solvers'][0] for i in issuers)
