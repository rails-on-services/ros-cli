clusterName: ${cluster_name}
clusterLocation: ${cluster_location}
gcpServiceAccountSecret:
  enabled: true
  name: fluentd-gcp-google-service-account
  key: application_default_credentials.json
