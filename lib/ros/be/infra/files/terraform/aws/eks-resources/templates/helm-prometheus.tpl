alertmanager:
  enabled: false
initChownData:
  enabled: false
kubeStateMetrics:
  enabled: false
nodeExporter:
  enabled: false
pushgateway:
  enabled: false

serviceAccounts:
  alertmanager:
    create: false
  kubeStateMetrics:
    create: false
  nodeExporter:
    create: false
  pushgateway:
    create: false
server:
  resources:
    limits:
      cpu: 1000m
      memory: 4Gi
    requests:
      cpu: 500m
      memory: 3Gi
  global:
    scrape_interval: "15s"
  strategy:
    type: Recreate
  retention: "15d"
serverFiles:
  prometheus.yml:
    remote_write:
    - url: http://vminsert.monitor.svc.cluster.local:8480/insert/1/prometheus
      queue_config:
        max_samples_per_send: 10000
        max_shards: 30
    scrape_configs:
    - job_name: kubernetes-apiservers
      honor_timestamps: true
      scrape_interval: 15s
      scrape_timeout: 10s
      metrics_path: /metrics
      scheme: https
      kubernetes_sd_configs:
      - role: endpoints
        namespaces:
          names:
          - default
      bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
      tls_config:
        ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        insecure_skip_verify: false
      relabel_configs:
      - source_labels: [__meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
        separator: ;
        regex: kubernetes;https
        replacement: $1
        action: keep
    - job_name: kubernetes-nodes
      honor_timestamps: true
      scrape_interval: 15s
      scrape_timeout: 10s
      metrics_path: /metrics
      scheme: https
      kubernetes_sd_configs:
      - role: node
      bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
      tls_config:
        ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        insecure_skip_verify: false
      relabel_configs:
      - separator: ;
        regex: __meta_kubernetes_node_label_(.+)
        replacement: $1
        action: labelmap
      - separator: ;
        regex: (.*)
        target_label: __address__
        replacement: kubernetes.default.svc:443
        action: replace
      - source_labels: [__meta_kubernetes_node_name]
        separator: ;
        regex: (.+)
        target_label: __metrics_path__
        replacement: /api/v1/nodes/${1}/proxy/metrics
        action: replace
<<<<<<< HEAD
    - job_name: kubernetes-cadvisor-test
=======
    - job_name: kubernetes-cadvisor
>>>>>>> Working prototipe of Fluentd-Loki-Prometheus-VictoriaMetrics-Grafana stack
      honor_timestamps: true
      scrape_interval: 15s
      scrape_timeout: 10s
      metrics_path: /metrics
      scheme: https
      kubernetes_sd_configs:
      - role: node
      bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
      tls_config:
        ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        insecure_skip_verify: false
      relabel_configs:
      - separator: ;
        regex: __meta_kubernetes_node_label_(.+)
        replacement: $1
        action: labelmap
      - separator: ;
        regex: (.*)
        target_label: __address__
        replacement: kubernetes.default.svc:443
        action: replace
      - source_labels: [__meta_kubernetes_node_name]
        separator: ;
        regex: (.+)
        target_label: __metrics_path__
<<<<<<< HEAD
        replacement: '/api/v1/nodes/$1/proxy/metrics/cadvisor'
=======
        replacement: /api/v1/nodes/${1}/proxy/metrics/cadvisor
>>>>>>> Working prototipe of Fluentd-Loki-Prometheus-VictoriaMetrics-Grafana stack
        action: replace
    - job_name: kubernetes-service-endpoints
      honor_timestamps: true
      scrape_interval: 15s
      scrape_timeout: 10s
      metrics_path: /metrics
      scheme: http
      kubernetes_sd_configs:
      - role: endpoints
      relabel_configs:
      - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_scrape]
        separator: ;
        regex: "true"
        replacement: $1
        action: keep
      - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_scheme]
        separator: ;
        regex: (https?)
        target_label: __scheme__
        replacement: $1
        action: replace
      - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_path]
        separator: ;
        regex: (.+)
        target_label: __metrics_path__
        replacement: $1
        action: replace
      - source_labels: [__address__, __meta_kubernetes_service_annotation_prometheus_io_port]
        separator: ;
        regex: ([^:]+)(?::\d+)?;(\d+)
        target_label: __address__
        replacement: $1:$2
        action: replace
      - separator: ;
        regex: __meta_kubernetes_service_label_(.+)
        replacement: $1
        action: labelmap
      - source_labels: [__meta_kubernetes_namespace]
        separator: ;
        regex: (.*)
        target_label: kubernetes_namespace
        replacement: $1
        action: replace
      - source_labels: [__meta_kubernetes_service_name]
        separator: ;
        regex: (.*)
        target_label: kubernetes_name
        replacement: $1
        action: replace
    - job_name: kubernetes-pods
      honor_timestamps: true
      scrape_interval: 15s
      scrape_timeout: 10s
      metrics_path: /metrics
      scheme: http
      kubernetes_sd_configs:
      - role: pod
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        separator: ;
        regex: "true"
        replacement: $1
        action: keep
      - source_labels: [__meta_kubernetes_pod_annotation_sidecar_istio_io_status, __meta_kubernetes_pod_annotation_prometheus_io_scheme]
        separator: ;
        regex: ((;.*)|(.*;http))
        replacement: $1
        action: keep
      - source_labels: [__meta_kubernetes_pod_annotation_istio_mtls]
        separator: ;
        regex: (true)
        replacement: $1
        action: drop
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        separator: ;
        regex: (.+)
        target_label: __metrics_path__
        replacement: $1
        action: replace
      - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
        separator: ;
        regex: ([^:]+)(?::\d+)?;(\d+)
        target_label: __address__
        replacement: $1:$2
        action: replace
      - separator: ;
        regex: __meta_kubernetes_pod_label_(.+)
        replacement: $1
        action: labelmap
      - source_labels: [__meta_kubernetes_namespace]
        separator: ;
        regex: (.*)
        target_label: namespace
        replacement: $1
        action: replace
      - source_labels: [__meta_kubernetes_pod_name]
        separator: ;
        regex: (.*)
        target_label: pod_name
        replacement: $1
        action: replace