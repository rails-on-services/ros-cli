vmselect:
  fullnameOverride: vmselect
  replicaCount: 1
  image:
    tag: v1.28.2-cluster
    #pullPolicy: Always
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
  image:
    tag: v1.28.2-cluster
    #pullPolicy: Always
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
  image:
    tag: v1.28.2-cluster
    #pullPolicy: Always
  persistentVolume:
    size: 50Gi
  resources:
    limits:
      cpu: 500m
      memory: 1.5Gi
    requests:
      cpu: 300m
      memory: 1Gi