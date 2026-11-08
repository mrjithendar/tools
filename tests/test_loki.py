"""EKS Alloy (deploy/eks) matches the mk4 Alloy config in the miniKube repository apart from the destination."""
from pathlib import Path
import sys
import unittest
import yaml

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts/lib'))
from repos import MINIKUBE  # noqa: E402

MK4_ALLOY = MINIKUBE / 'deploy/minikube/observability/loki/config.alloy'


@unittest.skipUnless(MK4_ALLOY.is_file(), f'{MK4_ALLOY} not found: clone mrjithendar/miniKube beside tools or set MINIKUBE_DIR')
class LokiTests(unittest.TestCase):
    def test_eks_alloy_differs_from_mk4_only_in_destination(self):
        mk4=MK4_ALLOY.read_text()
        eks=yaml.safe_load((ROOT/'deploy/eks/manifests/alloy/alloy-config-configmap.yaml').read_text())['data']['config.alloy']
        self.assertEqual(eks[:eks.index('loki.write "mk4"')].replace('loki.write.mk4','loki.write.local'),mk4[:mk4.index('loki.write "local"')])
        self.assertIn('url = "https://jithendar.com/loki/api/v1/push"',eks)
        self.assertIn('cluster = "roboshop-demo"',eks)


if __name__=='__main__':
    unittest.main()
