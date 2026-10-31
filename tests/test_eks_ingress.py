"""EKS ingress and mesh: routing, the /roboshop prefix boundary, identities and the argocd-eks patch."""
import http.server
import io
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import threading
import urllib.error
import urllib.request

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts/lib'))
from repos import APP  # noqa: E402

EKS = ROOT / 'eks'
INGRESS = EKS / 'roboshop-demo/ingress'
MESH = EKS / 'roboshop-demo/mesh'
EDGE = EKS / 'edge'
GATEWAY = 'istio-ingress/sa/istio-ingressgateway'
# Every in-mesh call, read from the service code and env (eks/README.md). Workload -> port, allowed callers.
MATRIX = {
    'web': (8080, {GATEWAY}),
    'ai-gateway': (3000, {'roboshop-ai/sa/web', 'roboshop-ai/sa/moks', 'roboshop-ai/sa/mcp-server'}),
    'user-service': (4109, {'roboshop-ai/sa/ai-gateway', 'roboshop-ai/sa/moks'}),
    'catalogue-service': (4108, {'roboshop-ai/sa/ai-gateway', 'roboshop-ai/sa/moks'}),
    'cart-service': (4107, {'roboshop-ai/sa/ai-gateway'}),
    'payment-service': (4105, {'roboshop-ai/sa/ai-gateway'}),
    'shipping-service': (4106, {'roboshop-ai/sa/ai-gateway', 'roboshop-ai/sa/user-service'}),
    'currency-service': (4111, {'roboshop-ai/sa/ai-gateway', 'roboshop-ai/sa/web'}),
    'moks': (4103, {'roboshop-ai/sa/web', 'roboshop-ai/sa/ai-gateway'}),
}
MESHED = sorted(set(MATRIX) | {'mcp-server'})
OUT_OF_MESH = {'redis': 'Deployment', 'rabbitmq': 'StatefulSet', 'shipping-db': 'Deployment', 'kafka': 'StatefulSet'}


def load(path):
    return yaml.safe_load(path.read_text())


def kustomize(path):
    return [doc for doc in yaml.safe_load_all(subprocess.check_output(['kubectl', 'kustomize', str(path)], text=True)) if doc]


def virtual_service():
    return load(INGRESS / 'roboshop-virtualservice.yaml')['spec']['http']


def route(url):
    """Envoy's first-match decision for this VirtualService: (status, location or upstream path)."""
    path, _, query = url.partition('?')
    suffix = f'?{query}' if query else ''
    for rule in virtual_service():
        uri = rule['match'][0]['uri']
        if uri.get('exact') == path:
            return rule['redirect']['redirectCode'], rule['redirect']['uri'] + suffix
        if 'prefix' in uri and path.startswith(uri['prefix']):
            return 200, rule['rewrite']['uri'] + path[len(uri['prefix']):] + suffix
    return 404, None


@pytest.mark.parametrize('url,expected', [
    ('/roboshop', (308, '/roboshop/')),
    ('/roboshop?utm=a&b=c', (308, '/roboshop/?utm=a&b=c')),
    ('/roboshop/', (200, '/')),
    ('/roboshop/?q=robot', (200, '/?q=robot')),
    ('/roboshop/products/alpha-1', (200, '/products/alpha-1')),
    ('/roboshop/app.js', (200, '/app.js')),
    ('/roboshop/api/auth/me', (200, '/api/auth/me')),
    ('/roboshop/moks/chat', (200, '/moks/chat')),
    # The rest of jithendar.com has no route here.
    ('/', (404, None)),
    ('/grafana/', (404, None)),
    ('/argocd/', (404, None)),
    ('/roboshopping', (404, None)),
    ('/api/auth/me', (404, None)),
])
def test_routes(url, expected):
    assert route(url) == expected


def test_only_the_web_service_is_routed():
    destinations = [d['destination'] for rule in virtual_service() for d in rule.get('route', [])]
    assert destinations == [{'host': 'web.roboshop-ai.svc.cluster.local', 'port': {'number': 8080}}]


def test_no_route_deadline_cuts_off_long_answers():
    assert not any('timeout' in rule for rule in virtual_service())


def test_prefix_is_stripped_at_exactly_one_boundary():
    ingressroute = load(EDGE / 'roboshop-eks-ingressroute.yaml')
    assert 'middlewares' not in ingressroute['spec']['routes'][0]
    assert sum('rewrite' in rule for rule in virtual_service()) == 1


def test_edge_only_takes_roboshop_and_keeps_the_host():
    route_ = load(EDGE / 'roboshop-eks-ingressroute.yaml')['spec']['routes'][0]
    assert route_['match'] == 'Host(`jithendar.com`) && (Path(`/roboshop`) || PathPrefix(`/roboshop/`))'
    assert route_['services'][0]['passHostHeader'] is True
    assert route_['services'][0]['scheme'] == 'https'


def test_edge_verifies_the_certificate_the_gateway_serves():
    transport = load(EDGE / 'roboshop-eks-origin-serverstransport.yaml')['spec']
    assert 'insecureSkipVerify' not in transport
    certificate = load(INGRESS / 'jithendar-com-certificate.yaml')['spec']
    assert transport['serverName'] in certificate['dnsNames']
    server = load(INGRESS / 'public-gateway.yaml')['spec']['servers'][0]
    assert server['tls']['credentialName'] == certificate['secretName']
    assert transport['serverName'] in server['hosts']


def test_traefik_may_use_the_external_name_service():
    assert load(ROOT / 'minikube/traefik/values.yaml')['providers']['kubernetesCRD']['allowExternalNameServices'] is True


def test_authorization_matches_the_call_matrix():
    policies = {d['metadata']['name']: d for d in kustomize(MESH) if d['kind'] == 'AuthorizationPolicy'}
    assert set(policies) == set(MATRIX) | {'allow-nothing'}
    assert policies['allow-nothing']['spec'] == {}
    for workload, (port, callers) in MATRIX.items():
        spec = policies[workload]['spec']
        assert spec['selector']['matchLabels'] == {'app': workload} and spec['action'] == 'ALLOW'
        rule = spec['rules'][0]
        assert {p.removeprefix('cluster.local/ns/') for p in rule['from'][0]['source']['principals']} == callers
        assert rule['to'][0]['operation'] == {'ports': [str(port)]}


def test_mcp_server_has_no_callers():
    policies = [d for d in kustomize(MESH) if d['kind'] == 'AuthorizationPolicy']
    assert not any(d['spec'].get('selector', {}).get('matchLabels', {}).get('app') == 'mcp-server' for d in policies)
    assert not any('/sa/mcp-server' in str(d) and d['metadata']['name'] != 'ai-gateway' for d in policies)


def test_every_meshed_workload_has_a_tokenless_identity():
    accounts = [d for d in kustomize(MESH) if d['kind'] == 'ServiceAccount']
    assert sorted(d['metadata']['name'] for d in accounts) == MESHED
    assert all(d['automountServiceAccountToken'] is False for d in accounts)


def test_readme_embeds_the_current_diagram():
    source = (EKS / 'diagrams/roboshop-ingress.mmd').read_text().splitlines()
    assert '\n'.join(line for line in source if not line.startswith('%%')) in (EKS / 'README.md').read_text()


def test_secrets_and_generated_names_stay_out_of_git():
    for path in EKS.rglob('*.yaml'):
        documents = [d for d in yaml.safe_load_all(path.read_text()) if d]
        assert not any(d.get('kind') == 'Secret' for d in documents), path
        assert 'elb.amazonaws.com' not in path.read_text(), path


@pytest.mark.parametrize('name,dest,project_dest', [
    ('roboshop-demo-ingress', 'roboshop-demo', 'istio-ingress'),
    ('roboshop-demo-mesh', 'roboshop-demo', 'roboshop-ai'),
])
def test_applications_are_manual_and_allowed_by_the_project(name, dest, project_dest):
    app = load(EKS / f'applications/{name}.yaml')
    assert 'automated' not in app['spec'].get('syncPolicy', {})
    assert app['spec']['destination'] == {'name': dest, 'namespace': project_dest}
    allowed = load(ROOT / 'argocd/project-platform.yaml')['spec']['destinations']
    assert {'namespace': project_dest, 'name': dest} in allowed


def test_edge_application_targets_mk4_and_never_syncs_itself():
    app = load(EKS / 'applications/roboshop-demo-edge.yaml')
    assert app['spec']['destination'] == {'server': 'https://kubernetes.default.svc', 'namespace': 'roboshop-ai'}
    assert 'automated' not in app['spec']['syncPolicy']


@pytest.fixture(scope='module')
def catalog(tmp_path_factory):
    """roboshop-ai's EKS Applications with the patch from this repository applied, as a temporary copy."""
    root = tmp_path_factory.mktemp('roboshop-ai')
    archive = subprocess.check_output(['git', '-C', str(APP), 'archive', 'HEAD', 'services', 'argocd-eks'])
    tarfile.open(fileobj=io.BytesIO(archive)).extractall(root, filter='data')
    if 'serviceAccountName' not in (root / 'argocd-eks/web.yaml').read_text():
        subprocess.check_call(['git', 'apply', '--unsafe-paths', f'--directory={root}', str(EKS / 'roboshop-ai-catalog.patch')], cwd=root)
    shutil.copytree(ROOT / 'minikube/roboshop', root / 'minikube/roboshop')
    return root


def render(catalog, app):
    source = load(catalog / f'argocd-eks/{app}.yaml')['spec']['source']
    path = catalog / source['path']
    kustomization = load(path / 'kustomization.yaml')
    kustomization['patches'] = source['kustomize']['patches']
    (path / 'kustomization.yaml').write_text(yaml.safe_dump(kustomization))
    return kustomize(path)


@pytest.mark.parametrize('workload', sorted(MATRIX))
def test_policies_select_real_workloads_and_ports(catalog, workload):
    # istioctl analyze has no live pods offline, so it cannot check selectors, hosts or Secrets.
    deployment = next(d for d in render(catalog, workload) if d['kind'] == 'Deployment')
    template = deployment['spec']['template']
    assert template['metadata']['labels']['app'] == workload
    assert MATRIX[workload][0] in [p['containerPort'] for c in template['spec']['containers'] for p in c.get('ports', [])]


def test_route_destination_is_the_real_web_service(catalog):
    service = next(d for d in render(catalog, 'web') if d['kind'] == 'Service')
    destination = virtual_service()[1]['route'][0]['destination']
    assert destination['host'] == f"{service['metadata']['name']}.{service['metadata']['namespace']}.svc.cluster.local"
    assert destination['port']['number'] in [p['port'] for p in service['spec']['ports']]


def test_gateway_identity_and_selector_match_the_helm_release():
    source = (ROOT / 'infrastructure/eks-ingress.tf').read_text()
    assert re.search(r'name\s+= "istio-ingressgateway"', source)  # chart: ServiceAccount, and label istio=ingressgateway
    assert load(INGRESS / 'public-gateway.yaml')['spec']['selector'] == {'istio': 'ingressgateway'}


@pytest.mark.parametrize('workload', MESHED)
def test_catalog_runs_each_workload_as_its_own_identity(catalog, workload):
    deployment = next(d for d in render(catalog, workload) if d['kind'] == 'Deployment')
    assert deployment['spec']['template']['spec']['serviceAccountName'] == workload
    assert 'sidecar.istio.io/inject' not in deployment['spec']['template']['metadata']['labels']


@pytest.mark.parametrize('app,workload', [('redis', 'redis'), ('rabbitmq', 'rabbitmq'), ('postgres', 'shipping-db'), ('kafka-bridge', 'kafka')])
def test_catalog_keeps_data_stores_out_of_the_mesh(catalog, app, workload):
    documents = render(catalog, app)
    pod = next(d for d in documents if d['kind'] == OUT_OF_MESH[workload] and d['metadata']['name'] == workload)
    assert pod['spec']['template']['metadata']['labels']['sidecar.istio.io/inject'] == 'false'


def test_catalog_keeps_the_import_job_out_of_the_mesh(catalog):
    job = next(d for d in render(catalog, 'postgres') if d['kind'] == 'Job')
    assert job['spec']['template']['metadata']['labels']['sidecar.istio.io/inject'] == 'false'


def test_catalog_declares_the_gateway_as_tcp(catalog):
    # web forwards the browser's Host, so an HTTP sidecar route would miss and bypass mTLS.
    service = next(d for d in render(catalog, 'ai-gateway') if d['kind'] == 'Service')
    assert service['spec']['ports'][0]['appProtocol'] == 'tcp'


def test_catalog_enrolls_the_namespace_without_losing_its_prune_protection(catalog):
    namespace = next(d for d in render(catalog, 'roboshop-config') if d['kind'] == 'Namespace')
    assert namespace['metadata']['labels'] == {'istio-injection': 'enabled'}
    assert namespace['metadata']['annotations']['argocd.argoproj.io/sync-options'] == 'Prune=false,Delete=false'


def test_mk4_namespace_stays_unlabelled():
    assert 'labels' not in load(ROOT / 'minikube/roboshop/roboshop-ai-namespace.yaml')['metadata']


class Echo(http.server.BaseHTTPRequestHandler):
    """Stands in for ai-gateway: reports what NGINX forwarded."""
    seen = []

    def do_GET(self):
        Echo.seen.append((self.path, self.headers.get('host')))
        body = b'{"ok":true}'
        self.send_response(200)
        self.send_header('content-length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


@pytest.fixture(scope='module')
def web(tmp_path_factory):
    """The real services/web NGINX templates and start.sh, at the upstream path the VirtualService produces."""
    dist = APP / 'services/web/frontend/dist'
    nginx = shutil.which('nginx')
    if not (nginx and shutil.which('envsubst') and dist.is_dir()):
        pytest.skip('needs nginx, envsubst and a built services/web/frontend/dist')
    work = tmp_path_factory.mktemp('web')
    shutil.copytree(dist, work / 'html')
    shutil.copytree(APP / 'services/web/nginx', work / 'nginx')
    gateway = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Echo)
    threading.Thread(target=gateway.serve_forever, daemon=True).start()
    mime = next(p for p in (Path('/opt/homebrew/etc/nginx/mime.types'), Path('/usr/local/etc/nginx/mime.types'), Path('/etc/nginx/mime.types')) if p.exists())
    port = 18080 + os.getpid() % 1000
    env = {**os.environ, 'NGINX_CONFIG_DIR': str(work / 'nginx'), 'NGINX_RUN_DIR': str(work / 'run'), 'WEB_ROOT': str(work / 'html'),
           'NGINX_MIME_TYPES': str(mime), 'NGINX_HTTP_PORT': str(port), 'NGINX_RESOLVER': '127.0.0.1', 'GATEWAY_HOST': '127.0.0.1',
           'GATEWAY_PORT': str(gateway.server_address[1]), 'FRONTEND_BASE_PATH': '/roboshop'}
    process = subprocess.Popen(['/bin/sh', str(work / 'nginx/start.sh')], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    for _ in range(100):
        try:
            urllib.request.urlopen(f'http://127.0.0.1:{port}/health', timeout=1)
            break
        except OSError:
            if process.poll() is not None:
                pytest.skip(f'nginx did not start: {process.stdout.read().decode()[-300:]}')
            threading.Event().wait(0.1)
    yield f'http://127.0.0.1:{port}'
    process.terminate()
    process.wait()
    gateway.shutdown()


def fetch(web, public_url):
    status, upstream = route(public_url)
    assert status == 200, public_url
    request = urllib.request.Request(web + upstream, headers={'Host': 'jithendar.com'})
    try:
        with urllib.request.urlopen(request) as response:
            return response.status, response.read().decode(errors='replace')
    except urllib.error.HTTPError as error:
        return error.code, ''


@pytest.mark.parametrize('url', ['/roboshop/', '/roboshop/products/alpha-1', '/roboshop/cart', '/roboshop/login', '/roboshop/account'])
def test_pages_load_under_the_prefix(web, url):
    status, body = fetch(web, url)
    assert status == 200
    assert 'src="/roboshop/' in body or 'href="/roboshop/' in body
    assert not re.search(r'(?:src|href)="/(?!roboshop/|/)', body)


@pytest.mark.parametrize('url', ['/roboshop/app.js', '/roboshop/paths.js', '/roboshop/styles.css'])
def test_assets_load_under_the_prefix(web, url):
    assert fetch(web, url)[0] == 200


def test_api_keeps_path_query_and_host(web):
    assert fetch(web, '/roboshop/api/products?q=robot')[0] == 200
    assert Echo.seen[-1] == ('/api/products?q=robot', 'jithendar.com')


@pytest.mark.parametrize('url,status', [
    ('/roboshop/metrics', 404),         # metrics stay private
    ('/roboshop/api/chat', 403),        # chat only goes through Moks
    ('/roboshop/roboshop/', 404),       # a double strip or none at all would show up here
    ('/roboshop/.env', 404),
])
def test_private_paths_stay_closed(web, url, status):
    assert fetch(web, url)[0] == status
