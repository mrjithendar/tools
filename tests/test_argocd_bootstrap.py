import importlib.util
from pathlib import Path
from unittest.mock import patch
import pytest

spec = importlib.util.spec_from_file_location('bootstrap', Path(__file__).resolve().parents[1] / 'scripts/argocd/bootstrap.py')
bootstrap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bootstrap)


@pytest.fixture(autouse=True)
def mock_credentials():
    with patch.object(bootstrap, 'refresh_pull_secrets'), patch.object(bootstrap, 'ensure_app_secrets'):
        yield


def test_preview_is_offline():
    with patch('sys.argv', ['bootstrap', '--dry-run']), patch.object(bootstrap.subprocess, 'check_output') as read, patch.object(bootstrap.subprocess, 'check_call') as write:
        bootstrap.main()
    read.assert_not_called()
    write.assert_not_called()


# Five Terraform-owned Deployments (cert-manager x3, argocd x2) are looked up before Traefik.
TERRAFORM_PRESENT = ['namespace/kube-system'] + ['deployment/x'] * 5


def test_fresh_install_order_and_context():
    with patch('sys.argv', ['bootstrap', '--context', 'fresh', '--deploy-apps']), patch.object(bootstrap.shutil, 'which', return_value='/bin/tool'), patch.object(bootstrap.subprocess, 'check_output', side_effect=TERRAFORM_PRESENT + ['--all-namespaces', '[]', '']), patch.object(bootstrap.subprocess, 'check_call') as write:
        bootstrap.main()
    commands = [call.args[0] for call in write.call_args_list]
    installs = [c for c in commands if c[0] == 'helm']
    assert [c[c.index('install') + 1] for c in installs] == ['traefik']
    assert all('--all' not in c for c in installs)
    rollouts = [c[-2] for c in commands[:commands.index(installs[0])]]
    assert rollouts == ['deployment/cert-manager', 'deployment/cert-manager-webhook', 'deployment/cert-manager-cainjector',
                        'deployment/argocd-server', 'deployment/argocd-repo-server']
    assert not any('install' in c for c in commands if c[0] != 'helm')
    assert 'deploy.py' in commands[-1][1] and 'install' not in commands[-1]
    assert all('fresh' in c for c in commands)


def test_missing_terraform_release_stops_before_any_install():
    with patch('sys.argv', ['bootstrap']), patch.object(bootstrap.shutil, 'which', return_value='/bin/tool'), patch.object(bootstrap.subprocess, 'check_output', side_effect=['namespace', 'deployment/cert-manager', '']), patch.object(bootstrap.subprocess, 'check_call') as write:
        with pytest.raises(RuntimeError, match='cert-manager/cert-manager-webhook is missing.*terraform -chdir=minikube-infrastructure apply'):
            bootstrap.main()
    assert not any(c.args[0][0] == 'helm' for c in write.call_args_list)


def test_install_failure_stops_later_stages():
    with patch('sys.argv', ['bootstrap', '--deploy-apps']), patch.object(bootstrap.shutil, 'which', return_value='/bin/tool'), patch.object(bootstrap.subprocess, 'check_output', side_effect=TERRAFORM_PRESENT + ['', '[]', '']), patch.object(bootstrap.subprocess, 'check_call', side_effect=[None] * 5 + [bootstrap.subprocess.CalledProcessError(1, 'helm')]) as write:
        with pytest.raises(bootstrap.subprocess.CalledProcessError):
            bootstrap.main()
    assert write.call_count == 6


def test_pull_secret_refresh_only_skips_controllers():
    with patch('sys.argv', ['bootstrap', '--pull-secrets-only']), patch.object(bootstrap.shutil, 'which', return_value='/bin/tool'), patch.object(bootstrap, 'refresh_pull_secrets') as refresh, patch.object(bootstrap.subprocess, 'check_output') as read:
        bootstrap.main()
    refresh.assert_called_once_with('mk4')
    read.assert_not_called()


# The autouse fixture mocks ensure_app_secrets; keep the real one for these tests.
_ensure_app_secrets = bootstrap.ensure_app_secrets


def _secret_calls(claims):
    # namespace apply (check_call), then: existing Secret lookup, PVC names.
    return ['', claims]


def test_new_credentials_refused_when_database_volumes_exist():
    with patch.object(bootstrap.subprocess, 'check_call'), \
         patch.object(bootstrap.subprocess, 'check_output', side_effect=_secret_calls('mongodb-data gateway-data')), \
         patch.object(bootstrap.subprocess, 'run') as create:
        with pytest.raises(RuntimeError, match='data volumes exist: mongodb-data'):
            _ensure_app_secrets('mk4')
    create.assert_not_called()


def test_new_credentials_created_on_fresh_cluster_or_when_accepted():
    for claims, accept in (('gateway-data', False), ('mongodb-data shipping-postgres', True)):
        with patch.object(bootstrap.subprocess, 'check_call'), \
             patch.object(bootstrap.subprocess, 'check_output', side_effect=_secret_calls(claims)), \
             patch.object(bootstrap.subprocess, 'run', return_value=bootstrap.subprocess.CompletedProcess([], 0)) as create:
            _ensure_app_secrets('mk4', accept_new_credentials=accept)
        assert create.called
