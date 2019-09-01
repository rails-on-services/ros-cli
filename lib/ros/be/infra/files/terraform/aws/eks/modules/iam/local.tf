locals {
  eks_roles = [
    "eks-viewer",
    "eks-editor",
    "eks-admin",
    "eks-developer"
  ]

  # The group should be matching the roles in order
  eks_groups = [
    "eks-viewer",
    "eks-editor",
    "eks-admin",
    "eks-developer"
  ]

  kubernetes_clusterrole_mappings = [
    "view",
    "edit",
    "cluster-admin",
    "developer"
  ]
}