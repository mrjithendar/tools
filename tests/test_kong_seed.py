"""Offline checks of the Kong seed (kong-config/seed/kong.yaml) and the Kong infrastructure manifests.

decK is the real validator (docs/kong/06-cutover-runbook.md runs `deck gateway validate` against Kong before any
import). These tests catch mistakes earlier and pin the routing behaviour the seed must keep: every request below
went to the same backend through Traefik on 2026-11-05. route_for() follows Kong 3.9.4's traditional_compatible
priority (kong/router/transform.lua, get_priority): more matched fields first, then regex paths over prefixes, then
regex_priority, then the longer prefix. Python's re stands in for Rust's regex, so only the shared syntax is used.
"""
from pathlib import Path
import re
import subprocess
import sys

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts/lib'))
SEED = yaml.safe_load((ROOT / 'kong-config/seed/kong.yaml').read_text())
# Imported separately, once RoboShop runs on mk4; Kong then holds both files' entities side by side.
ROBOSHOP = yaml.safe_load((ROOT / 'kong-config/seed/roboshop.yaml').read_text())
# kong/constants.lua at tag 3.9.4, bundled plugins (OSS).
OSS_PLUGINS = {'jwt', 'acl', 'correlation-id', 'cors', 'oauth2', 'tcp-log', 'udp-log', 'file-log', 'http-log', 'key-auth',
               'hmac-auth', 'basic-auth', 'ip-restriction', 'request-transformer', 'response-transformer',
               'request-size-limiting', 'rate-limiting', 'response-ratelimiting', 'syslog', 'loggly', 'datadog',
               'ldap-auth', 'statsd', 'bot-detection', 'aws-lambda', 'request-termination', 'prometheus', 'proxy-cache',
               'session', 'acme', 'grpc-gateway', 'grpc-web', 'pre-function', 'post-function', 'azure-functions',
               'zipkin', 'opentelemetry', 'standard-webhooks', 'redirect'}


def routes():
    for service in SEED['services'] + ROBOSHOP['services']:
        for route in service.get('routes', []):
            yield service, route


def all_plugins():
    yield from SEED.get('plugins', [])
    for service in SEED['services'] + ROBOSHOP['services']:
        yield from service.get('plugins', [])
        for route in service.get('routes', []):
            yield from route.get('plugins', [])


def test_format_and_scope():
    assert SEED['_format_version'] == '3.0'
    assert SEED['_info']['select_tags'] == ['seed:v1']
    assert 'consumers' not in SEED and 'certificates' not in SEED and 'snis' not in SEED


def test_names_unique_and_plugins_oss_only():
    # Kong requires unique names per entity type; a Service and a Route may share one.
    for names in ([s['name'] for s in SEED['services'] + ROBOSHOP['services']], [r['name'] for _, r in routes()]):
        assert len(names) == len(set(names))
    instances = [p['instance_name'] for p in all_plugins()]
    assert len(instances) == len(set(instances))
    assert {p['name'] for p in all_plugins()} <= OSS_PLUGINS


def test_no_credentials_in_seed():
    text = (ROOT / 'kong-config/seed/kong.yaml').read_text().lower()
    for word in ('password:', 'key:', 'secret:', 'username:', 'basicauth_credentials', 'keyauth_credentials'):
        assert word not in text, word


def test_upstreams_are_cluster_dns_names():
    for service in SEED['services'] + ROBOSHOP['services']:
        assert re.fullmatch(r'[a-z0-9-]+\.[a-z0-9-]+\.svc\.cluster\.local', service['host']), service['name']
        assert isinstance(service['port'], int)


def test_regex_paths_compile():
    for _, route in routes():
        for path in route.get('paths', []):
            if path.startswith('~'):
                re.compile(path[1:])
            else:
                assert path.startswith('/')


def priority(route):
    weight = sum(bool(route.get(f)) for f in ('methods', 'hosts', 'paths', 'snis', 'headers', 'sources', 'destinations'))
    regex = route['_path'].startswith('~')
    return (weight, True, regex, route.get('regex_priority', 0) if regex else 0, 0 if regex else len(route['_path']))


def route_for(method, host, path, scheme='https'):
    candidates = []
    for service, route in routes():
        if 'tls' in route['protocols'] or (route.get('methods') and method not in route['methods']):
            continue
        if host not in route.get('hosts', []):
            continue
        for p in route.get('paths', ['/']):  # traditional_compatible splits mixed-path routes like this
            ok = re.match(p[1:], path) if p.startswith('~') else path.startswith(p)
            if ok:
                candidates.append(dict(route, _path=p, _service=service['name']))
    if not candidates:
        return None, None
    best = max(candidates, key=priority)
    action = 'redirect-https' if scheme not in best['protocols'] else 'proxy'
    return best['name'], action


# (method, host, path) -> Kong route. Backends as Traefik routed them on 2026-11-05.
CASES = [
    ('GET', 'jithendar.com', '/', 'jithendar-com'),
    ('GET', 'jithendar.com', '/blog/some-post', 'jithendar-com'),
    ('GET', 'jithendar.com', '/moksfoo', 'jithendar-com'),            # Ingress Prefix /moks does not match
    ('GET', 'jithendar.com', '/dbx', 'jithendar-com'),
    ('GET', 'www.jithendar.com', '/blog', 'jithendar-com-www-redirect'),
    ('GET', 'jithendar.com', '/db', 'jithendar-db-ui-slash'),
    ('GET', 'jithendar.com', '/db/', 'jithendar-db-ui'),
    ('POST', 'jithendar.com', '/db/?server=x', 'jithendar-db-ui'),
    ('GET', 'jithendar.com', '/moks', 'moks'),
    ('GET', 'jithendar.com', '/moks/api/investigations/1/events', 'moks'),
    ('GET', 'jithendar.com', '/moks/api/terminal/sessions/abc', 'moks-terminal'),
    ('GET', 'jithendar.com', '/opensearch', 'moks-opensearch-read'),
    ('HEAD', 'jithendar.com', '/opensearch/_cluster/health', 'moks-opensearch-read'),
    ('POST', 'jithendar.com', '/opensearch/_search', 'moks-opensearch-search'),
    ('POST', 'jithendar.com', '/opensearch/idx/_msearch', 'moks-opensearch-search'),
    ('POST', 'jithendar.com', '/opensearch/idx/_doc', 'jithendar-com'),     # writes never reach OpenSearch
    ('DELETE', 'jithendar.com', '/opensearch/idx', 'jithendar-com'),
    ('GET', 'jithendar.com', '/opensearch-dashboards/app/home', 'moks-opensearch-dashboards'),
    ('GET', 'jithendar.com', '/argocd/applications', 'argocd'),
    ('GET', 'jithendar.com', '/grafana/d/abc', 'grafana'),
    ('GET', 'jithendar.com', '/prometheus/graph', 'prometheus'),
    ('POST', 'jithendar.com', '/prometheus/api/v1/write', 'prometheus-remote-write'),
    ('POST', 'jithendar.com', '/loki/api/v1/push', 'loki-push'),
    ('GET', 'jithendar.com', '/loki/api/v1/query_range', 'loki-read'),
    ('GET', 'jithendar.com', '/loki/api/v1/label/app/values', 'loki-read'),
    ('GET', 'jithendar.com', '/loki/api/v1/labels', 'loki-read'),
    ('GET', 'jithendar.com', '/loki/api/v1/tail', 'jithendar-com'),         # not exposed through Traefik either
    # RoboShop, as the EKS Istio VirtualService routed it.
    ('GET', 'jithendar.com', '/roboshop', 'roboshop-slash'),
    ('GET', 'jithendar.com', '/roboshop/', 'roboshop'),
    ('GET', 'jithendar.com', '/roboshop/products/robot-arm', 'roboshop'),
    ('POST', 'jithendar.com', '/roboshop/api/cart', 'roboshop'),
    ('GET', 'jithendar.com', '/roboshopx', 'jithendar-com'),
]


@pytest.mark.parametrize('method,host,path,expected', CASES)
def test_routing_matches_traefik(method, host, path, expected):
    assert route_for(method, host, path.split('?')[0])[0] == expected


@pytest.mark.parametrize('host,path', [('jithendar.com', '/'), ('jithendar.com', '/moks'), ('jithendar.com', '/argocd/')])
def test_plain_http_redirects_to_https(host, path):
    assert route_for('GET', host, path, scheme='http')[1] == 'redirect-https'


def test_www_redirects_on_http_too():
    assert route_for('GET', 'www.jithendar.com', '/x', scheme='http') == ('jithendar-com-www-redirect', 'proxy')


def test_opensearch_search_capture_strips_prefix():
    _, route = next((s, r) for s, r in routes() if r['name'] == 'moks-opensearch-search')
    match = re.match(route['paths'][0][1:], '/opensearch/idx/_search')
    assert match.group(1) == '/idx/_search'
    assert re.match(route['paths'][0][1:], '/opensearch/_count').group(1) == '/_count'


def test_authenticated_routes_have_acl():
    for service, route in routes():
        service_plugins = {p['name'] for p in service.get('plugins', [])}
        if 'basic-auth' in service_plugins:
            names = service_plugins | {p['name'] for p in route.get('plugins', [])}
            assert 'acl' in names, route['name']
            assert all(p['config']['hide_credentials'] for p in service['plugins'] if p['name'] == 'basic-auth')


def test_db_routes_are_ip_restricted_and_postgres_is_tls_on_sni():
    by_name = {s['name']: s for s in SEED['services']}
    for name in ('jithendar-db-ui', 'jithendar-postgres'):
        assert 'ip-restriction' in {p['name'] for p in by_name[name]['plugins']}
    stream = by_name['jithendar-postgres']
    assert stream['protocol'] == 'tcp' and stream['routes'][0]['protocols'] == ['tls']
    assert stream['routes'][0]['snis'] == ['db.jithendar.com']


def test_global_plugin_strips_client_forwarding_headers():
    (plugin,) = SEED['plugins']
    assert plugin['name'] == 'pre-function'
    code = plugin['config']['rewrite'][0]
    for header in ('X-Forwarded-For', 'X-Forwarded-Proto', 'X-Forwarded-Host', 'X-Real-IP', 'Forwarded'):
        assert f'clear("{header}")' in code


KONG = ROOT / 'deploy/minikube/kong'


def kong_docs():
    return list(yaml.safe_load_all(subprocess.check_output(['kubectl', 'kustomize', str(KONG)], text=True)))


def test_admin_and_manager_never_public():
    docs = kong_docs()
    config = next(d for d in docs if d['kind'] == 'ConfigMap' and d['metadata']['name'] == 'kong-config')['data']
    assert config['KONG_ADMIN_LISTEN'].startswith('127.0.0.1:8001')
    assert config['KONG_ADMIN_GUI_LISTEN'] == '127.0.0.1:8002'
    assert config['KONG_ADMIN_GUI_URL'] == 'http://localhost:8002'
    assert config['KONG_ADMIN_GUI_API_URL'] == 'http://localhost:8001'
    for service in (d for d in docs if d['kind'] == 'Service'):
        ports = {p['port'] for p in service['spec']['ports']}
        if ports & {8001, 8002, 8444, 8445}:
            assert service['spec']['type'] == 'ClusterIP', service['metadata']['name']
        if service['spec']['type'] == 'NodePort':
            assert service['metadata']['name'] == 'kong-proxy'
    assert not [d for d in docs if d['kind'] in ('Ingress', 'IngressRoute', 'HTTPRoute')]


def test_bootstrap_job_runs_once_and_is_not_a_hook():
    job = next(d for d in kong_docs() if d['kind'] == 'Job')
    annotations = job['metadata']['annotations']
    assert 'argocd.argoproj.io/hook' not in annotations and 'helm.sh/hook' not in annotations
    assert 'ttlSecondsAfterFinished' not in job['spec']
    assert job['metadata']['name'].endswith('3-9-4')
    command = job['spec']['template']['spec']['containers'][0]['command']
    assert command[:3] == ['kong', 'migrations', 'bootstrap'] and '--force' not in command


def test_images_pinned_and_database_persistent():
    docs = kong_docs()
    images = {c['image'] for d in docs if d['kind'] in ('Deployment', 'StatefulSet', 'Job')
              for c in d['spec']['template']['spec'].get('initContainers', []) + d['spec']['template']['spec']['containers']}
    assert images == {'kong:3.9.4', 'postgres:17.11-alpine', 'python:3.13-alpine'}
    pvc = next(d for d in docs if d['kind'] == 'PersistentVolumeClaim')
    assert pvc['spec']['storageClassName'] == 'standard-retain'
    assert pvc['metadata']['annotations']['argocd.argoproj.io/sync-options'] == 'Prune=false,Delete=false'
    storage_class = next(d for d in docs if d['kind'] == 'StorageClass')
    assert storage_class['reclaimPolicy'] == 'Retain' and storage_class['provisioner'] == 'k8s.io/minikube-hostpath'
    assert not [d for d in docs if d['kind'] == 'Secret']


def test_review_export_redacts_credentials_and_keys():
    dump = dict(SEED, consumers=[{'username': 'u', 'basicauth_credentials': [{'username': 'u', 'password': 'x'}]}],
                keyauth_credentials=[{'key': 'abc'}],
                certificates=[{'id': '2bc41d85-5025-5dbe-be05-5bf66f627345', 'cert': 'C', 'key': 'K', 'snis': [{'name': 'jithendar.com'}]}])
    dump['plugins'] = SEED['plugins'] + [{'name': 'http-log', 'config': {'http_endpoint': 'https://x', 'headers': {'Authorization': 'Bearer t'}, 'token': 't'}}]
    out = subprocess.run([sys.executable, str(ROOT / 'kong-config/redact_export.py')], input=yaml.safe_dump(dump),
                         capture_output=True, text=True, check=True).stdout
    state = yaml.safe_load(out)
    assert 'consumers' not in state and 'keyauth_credentials' not in state
    assert state['certificates'][0]['key'].startswith('<REDACTED') and state['certificates'][0]['cert'].startswith('<REDACTED')
    assert state['plugins'][-1]['config']['token'] == '<REDACTED>'
    assert 'abc' not in out and "'x'" not in out and ': K' not in out
    assert state['services'] == SEED['services']  # routes, plugins and allow lists survive untouched


def test_roboshop_seed_is_separate_and_matches_eks():
    assert ROBOSHOP['_format_version'] == '3.0' and ROBOSHOP['_info']['select_tags'] == ['seed:roboshop-v1']
    assert not set(ROBOSHOP) & {'plugins', 'consumers', 'certificates'}
    (web,) = ROBOSHOP['services']
    assert (web['host'], web['port']) == ('web.roboshop-ai.svc.cluster.local', 8080)
    routes_by_name = {r['name']: r for r in web['routes']}
    assert routes_by_name['roboshop']['strip_path'] is True  # Istio: rewrite /roboshop/ -> /
    (redirect,) = routes_by_name['roboshop-slash']['plugins']
    assert redirect['config'] == {'status_code': 308, 'location': 'https://jithendar.com/roboshop/', 'keep_incoming_path': False}
    istio = yaml.safe_load((ROOT / 'deploy/eks/manifests/ingress/roboshop-virtualservice.yaml').read_text())['spec']['http']
    assert istio[0]['match'][0]['uri'] == {'exact': '/roboshop'} and istio[0]['redirect']['redirectCode'] == 308
    assert istio[1]['route'][0]['destination'] == {'host': web['host'], 'port': {'number': web['port']}}


def test_kong_and_roboshop_web_policies_pair_up():
    from repos import APP_REPO, checkout  # scripts/lib (sys.path above)
    web = yaml.safe_load((checkout(APP_REPO) / 'services/web/web-kong-networkpolicy.yaml').read_text())['spec']
    peer = web['ingress'][0]['from'][0]
    assert peer['namespaceSelector']['matchLabels'] == {'kubernetes.io/metadata.name': 'kong'}
    kong_pod = next(d for d in kong_docs() if d['kind'] == 'Deployment')['spec']['template']['metadata']['labels']
    assert peer['podSelector']['matchLabels'].items() <= kong_pod.items()
    egress = next(d for d in kong_docs() if d['kind'] == 'NetworkPolicy' and d['metadata']['name'] == 'kong')['spec']['egress']
    rule = next(r for r in egress if r['to'][0].get('namespaceSelector', {}).get('matchLabels', {}).get('kubernetes.io/metadata.name') == 'roboshop-ai')
    assert rule['to'][0]['podSelector']['matchLabels'] == web['podSelector']['matchLabels'] and rule['ports'][0]['port'] == 8080
