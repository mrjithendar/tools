from pathlib import Path
import subprocess
import unittest
import yaml

ROOT=Path(__file__).resolve().parents[1]

class LokiTests(unittest.TestCase):
    def test_render_and_boundaries(self):
        docs=list(yaml.safe_load_all(subprocess.check_output(['kubectl','kustomize',str(ROOT/'deploy/minikube/observability/loki')],text=True)))
        deployments=[d for d in docs if d['kind']=='Deployment']
        self.assertEqual({d['metadata']['name'] for d in deployments},{'loki','alloy'})
        self.assertFalse(any(d['kind'] in ('IngressRoute','Role','RoleBinding','Secret') for d in docs))
        for d in deployments:
            self.assertEqual(d['spec']['replicas'],1)
            pod=d['spec']['template']['spec']
            self.assertTrue(pod['securityContext']['runAsNonRoot'])
            self.assertFalse(any('hostPath' in v for v in pod['volumes']))
        roles=[d for d in docs if d['kind']=='ClusterRole']
        self.assertEqual([r['metadata']['name'] for r in roles],['alloy-logs'])
        self.assertTrue(all(set(rule['resources'])<={'pods','pods/log'} for r in roles for rule in r['rules']))
        self.assertTrue(all(set(rule['verbs'])<={'get','list','watch'} for r in roles for rule in r['rules']))
        binding=next(d for d in docs if d['kind']=='ClusterRoleBinding')
        self.assertEqual(binding['subjects'],[{'kind':'ServiceAccount','name':'alloy','namespace':'monitoring'}])

    def test_public_route_is_authenticated_and_read_only(self):
        docs=list(yaml.safe_load_all(subprocess.check_output(['kubectl','kustomize',str(ROOT/'deploy/minikube/observability/loki')],text=True)))
        ingress=next(d for d in docs if d['kind']=='Ingress' and d['metadata']['name']=='loki-read')
        self.assertEqual({d['metadata']['name'] for d in docs if d['kind']=='Ingress'},{'loki-read','loki-push'})
        self.assertEqual(ingress['metadata']['annotations']['traefik.ingress.kubernetes.io/router.middlewares'],'monitoring-loki-read-auth@kubernetescrd')
        paths={p['path']:p['pathType'] for r in ingress['spec']['rules'] for p in r['http']['paths']}
        self.assertEqual(paths,{'/loki/api/v1/query_range':'Exact','/loki/api/v1/labels':'Exact','/loki/api/v1/format_query':'Exact','/loki/api/v1/label':'Prefix'})
        middleware=next(d for d in docs if d['kind']=='Middleware' and d['metadata']['name']=='loki-read-auth')
        self.assertEqual(middleware['spec']['basicAuth']['secret'],'loki-read-auth')
        self.assertNotEqual(middleware['spec']['basicAuth']['secret'],'monitoring-auth')
        project=yaml.safe_load((ROOT/'deploy/minikube/applications/project-observability.yaml').read_text())
        allowed={(r['group'],r['kind']) for r in project['spec']['namespaceResourceWhitelist']}
        self.assertLessEqual({('networking.k8s.io','Ingress'),('traefik.io','Middleware')},allowed)

    def test_push_route_is_authenticated_and_push_only(self):
        docs=list(yaml.safe_load_all(subprocess.check_output(['kubectl','kustomize',str(ROOT/'deploy/minikube/observability/loki')],text=True)))
        ingress=next(d for d in docs if d['kind']=='Ingress' and d['metadata']['name']=='loki-push')
        self.assertEqual(ingress['metadata']['annotations']['traefik.ingress.kubernetes.io/router.middlewares'],'monitoring-loki-push-auth@kubernetescrd')
        paths={p['path']:p['pathType'] for r in ingress['spec']['rules'] for p in r['http']['paths']}
        self.assertEqual(paths,{'/loki/api/v1/push':'Exact'})
        middleware=next(d for d in docs if d['kind']=='Middleware' and d['metadata']['name']=='loki-push-auth')
        self.assertEqual(middleware['spec']['basicAuth']['secret'],'loki-push-auth')

    def test_eks_alloy_differs_from_mk4_only_in_destination(self):
        mk4=(ROOT/'deploy/minikube/observability/loki/config.alloy').read_text()
        eks=yaml.safe_load((ROOT/'deploy/eks/manifests/alloy/alloy-config-configmap.yaml').read_text())['data']['config.alloy']
        self.assertEqual(eks[:eks.index('loki.write "mk4"')].replace('loki.write.mk4','loki.write.local'),mk4[:mk4.index('loki.write "local"')])
        self.assertIn('url = "https://jithendar.com/loki/api/v1/push"',eks)
        self.assertIn('cluster = "roboshop-demo"',eks)

    def test_retention_and_sanitization(self):
        cfg=yaml.safe_load((ROOT/'deploy/minikube/observability/loki/loki.yaml').read_text())
        self.assertEqual(cfg['limits_config']['retention_period'],'168h')
        self.assertTrue(cfg['compactor']['retention_enabled'])
        alloy=(ROOT/'deploy/minikube/observability/loki/config.alloy').read_text()
        self.assertIn('stage.output { source = "safe_line" }',alloy)
        # Experimental blocks crash Alloy at its default stability level.
        self.assertNotIn('wal {',alloy)
        self.assertNotIn('namespaces {',alloy)
        self.assertNotIn('target_label = "trace_id"',alloy)

    def test_datasource_preserves_prometheus(self):
        cfg=yaml.safe_load((ROOT/'deploy/minikube/observability/grafana/values.yaml').read_text())
        ds=cfg['datasources']['datasources.yaml']['datasources']
        self.assertEqual({d['type'] for d in ds},{'prometheus','loki','jaeger'})
        self.assertEqual([d['type'] for d in ds if d['isDefault']],['prometheus'])
        # Jaeger 2.x has only /api/v3; Grafana's Jaeger data source uses it only with this toggle.
        self.assertIn('jaegerEnableGrpcEndpoint',cfg['grafana.ini']['feature_toggles']['enable'])
        loki=next(d for d in ds if d['type']=='loki')
        self.assertIn('jaeger',[f.get('datasourceUid') for f in loki['jsonData']['derivedFields']])

if __name__=='__main__':unittest.main()
