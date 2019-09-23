image:
  tag: 6.3.5
persistence:
  enabled: true
  size: 20Gi
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
  auth.google:
    enabled: true
    client_id: ${client_id}
    client_secret: ${client_secret}
    scopes: https://www.googleapis.com/auth/userinfo.profile https://www.googleapis.com/auth/userinfo.email
    auth_url: https://accounts.google.com/o/oauth2/auth
    token_url: https://accounts.google.com/o/oauth2/token
    allowed_domains: perxtech.com,getperx.com
    allow_sign_up: true