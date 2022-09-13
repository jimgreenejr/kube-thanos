local t = import 'kube-thanos/thanos.libsonnet';

// For an example with every option and component, please check all.jsonnet

local commonConfig = {
  config+:: {
    local cfg = self,
    namespace: 'monitoring',
    version: 'v0.27.0',
    image: 'quay.io/thanos/thanos:' + cfg.version,
    imagePullPolicy: 'IfNotPresent',
    replicaLabels: ['prometheus_replica', 'rule_replica'],
    objectStorageConfig: {
      name: 'thanos-objectstorage',
      key: 'thanos.yaml',
    },
    hashringConfigMapName: 'hashring-config',
    volumeClaimTemplate: {
      spec: {
        accessModes: ['ReadWriteOnce'],
        resources: {
          requests: {
            storage: '10Gi',
          },
        },
      },
    },
  },
  tracing+: {
    type: 'JAEGER',
    config+: {
      sampler_type: 'ratelimiting',
      sampler_param: 2,
    },
  },
};

local s = t.store(commonConfig.config {
  replicas: 3,
  serviceMonitor: true,
});

local q = t.query(commonConfig.config {
  replicas: 3,
  replicaLabels: ['prometheus_replica', 'rule_replica'],
  serviceMonitor: true,
  stores: [s.storeEndpoint],
});

local c = t.compact(commonConfig.config {
  replicas: 1,
  serviceMonitor: true,
  disableDownsampling: true,
  deduplicationReplicaLabels: super.replicaLabels,
});

local qf = t.queryFrontend(commonConfig.config {
  replicas: 3,
  downstreamURL: 'http://%s.%s.svc.cluster.local.:%d' % [
    q.service.metadata.name,
    q.service.metadata.namespace,
    q.service.spec.ports[1].port,
  ],
  splitInterval: '12h',
  maxRetries: 10,
  logQueriesLongerThan: '10s',
  serviceMonitor: true,
  queryRangeCache: {
    type: 'memcached',
    config+: {
      addresses: ['monitoring-memcached.%s.svc.cluster.local:11211' % commonConfig.config.namespace],
    },
  },
  labelsCache: {
    type: 'memcached',
    config+: {
      addresses: ['monitoring-memcached.%s.svc.cluster.local:11211' % commonConfig.config.namespace],
    },
  },
});

{ ['thanos-store-' + name]: s[name] for name in std.objectFields(s) } +
{ ['thanos-compact-' + name]: c[name] for name in std.objectFields(c) } +
{ ['thanos-query-frontend-' + name]: qf[name] for name in std.objectFields(qf) if qf[name] != null } +
{ ['thanos-query-' + name]: q[name] for name in std.objectFields(q) }
