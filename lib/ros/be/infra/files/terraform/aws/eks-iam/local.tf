locals {
  eks_roles = [
    "${var.name}-eks-viewer",
    "${var.name}-eks-editor",
    "${var.name}-eks-admin",
    "${var.name}-eks-developer"
  ]

  # The group should be matching the roles in order
  eks_groups = [
    "${var.name}-eks-viewer",
    "${var.name}-eks-editor",
    "${var.name}-eks-admin",
    "${var.name}-eks-developer"
  ]

  kubernetes_clusterrole_mappings = [
    "view",
    "edit",
    "cluster-admin",
    "developer"
  ]
}