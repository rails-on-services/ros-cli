vmselect:
  fullnameOverride: vmselect
  replicaCount: 1
  resources:
    limits:
      cpu: 500m
      memory: 1.5Gi
    requests:
      cpu: 300m
      memory: 1Gi
vminsert:
  fullnameOverride: vminsert
  replicaCount: 1
  resources:
    limits:
      cpu: 500m
      memory: 1.5Gi
    requests:
      cpu: 300m
      memory: 1Gi
vmstorage:
  fullnameOverride: vmstorage
  replicaCount: 1
  resources:
    limits:
      cpu: 500m
      memory: 1.5Gi
    requests:
      cpu: 300m
      memory: 1Gi