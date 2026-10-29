"""MongoDB setup imports the product catalogue defined in roboshop-ai (services/mongodb/catalog.js)."""
import sys
from pathlib import Path
import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts/lib'))
from repos import APP_REPO, ARGOCD, checkout  # noqa: E402


def test_configmap_matches_catalog_js():
    data = yaml.safe_load((ROOT / 'minikube/mongodb/mongodb-catalog-configmap.yaml').read_text())['data']
    catalog = (checkout(APP_REPO) / 'services/mongodb/catalog.js').read_text()
    assert data['20-catalog.js'].rstrip('\n') == catalog.rstrip('\n'), 'run `npm run catalog:configmap` in roboshop-ai'


def test_mongodb_mounts_catalog_into_init_directory():
    deployment = yaml.safe_load((ROOT / 'minikube/mongodb/mongodb-deployment.yaml').read_text())
    pod = deployment['spec']['template']['spec']
    mounts = {m['name']: m['mountPath'] for m in pod['containers'][0]['volumeMounts']}
    assert mounts['init'] == '/docker-entrypoint-initdb.d'
    init = next(v for v in pod['volumes'] if v['name'] == 'init')
    items = {(s['configMap']['name'], i['key'], i['path']) for s in init['projected']['sources'] for i in s['configMap']['items']}
    assert ('mongodb-catalog', '20-catalog.js', '20-catalog.js') in items


def test_argo_deploys_the_catalog_configmap():
    app = yaml.safe_load((ARGOCD / 'mongodb.yaml').read_text())
    assert app['spec']['source']['repoURL'] == 'https://github.com/mrjithendar/tools.git'
    assert app['spec']['source']['path'] == 'minikube/mongodb'
    assert 'mongodb-catalog-configmap.yaml' in app['spec']['source']['directory']['include']
