clusterName: ${cluster_name}
clusterLocation: ${cluster_location}
%{ if gcp_service_account_secret != "" }
gcpServiceAccountSecret:
  enabled: true
  name: ${gcp_service_account_secret}
  key: application_default_credentials.json
%{ endif ~}
