vmselect:
  fullnameOverride: vmselect
  replicaCount: 1
  image:
    tag: v1.28.3-cluster
    #pullPolicy: Always
  resources:
    limits:
      cpu: 1.5
      memory: 3Gi
    requests:
      cpu: 1
      memory: 2Gi
vminsert:
  fullnameOverride: vminsert
  replicaCount: 1
  image:
    tag: v1.28.3-cluster
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
    tag: v1.28.3-cluster
    #pullPolicy: Always
  persistentVolume:
    size: 50Gi
  resources:
    limits:
      cpu: 500m
      memory: 2.5Gi
    requests:
      cpu: 300m
      memory: 1.5Gi
