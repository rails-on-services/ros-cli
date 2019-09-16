image:
  tag: 6.3.5
persistence:
  enabled: true
  size: 20Gi
  storageClassName: gp2
  accessModes:
  - ReadWriteOnce
service:
  type: ClusterIP
resources:
  limits:
    memory: 2.5Gi
  requests:
    cpu: 0.5
    memory: 2Gi
admin:
  existingSecret: grafana-credentials
  userKey: username
  passwordKey: password
sidecar:
  dashboards:
    enabled: true
    label: grafana_dashboard
  datasources:
    enabled: true
    label: grafana_datasource
grafana.ini:
  database:
    type: sqlite3