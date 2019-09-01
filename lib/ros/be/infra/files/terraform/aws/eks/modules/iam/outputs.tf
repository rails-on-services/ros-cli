output "iam_roles" {
  value = aws_iam_role.eks-roles.*.arn
}

output "iam_groups" {
  value = aws_iam_group.eks-groups.*.name
}

output "eks_map_roles" {
  description = "The intended eks_map_roles can be pass to module terraform-aws-modules/eks/aws"

  value = [for i in range(0, 4) : 
    {
      role_arn = element(aws_iam_role.eks-roles.*.arn, i)
      username = "aws:{{AccountID}}:session:{{SessionName}}"
      group    = element(aws_iam_group.eks-groups.*.name, i)
    }
  ] 
}

output "kubernetes_clusterrolebindings" {
  description = "The intended kubernetes clusterrolesbindings can be pass to module eks-resources"

  value = [for i in range(0, 4) : 
    {
      name        = local.eks_roles[i]
      group       = element(aws_iam_group.eks-groups.*.name, i)
      clusterrole = local.kubernetes_clusterrole_mappings[i]
    }
  ]

  # TODO, better way to create this
  #value = [
  #  {
  #    name        = "${local.eks_roles[0]}"
  #    group       = "${element(aws_iam_group.eks-groups.*.name, 0)}"
  #    clusterrole = "${local.kubernetes_clusterrole_mappings[0]}"
  #  },
  #  {
  #    name        = "${local.eks_roles[1]}"
  #    group       = "${element(aws_iam_group.eks-groups.*.name, 1)}"
  #    clusterrole = "${local.kubernetes_clusterrole_mappings[1]}"
  #  },
  #  {
  #    name        = "${local.eks_roles[2]}"
  #    group       = "${element(aws_iam_group.eks-groups.*.name, 2)}"
  #    clusterrole = "${local.kubernetes_clusterrole_mappings[2]}"
  #  },
  #  {
  #    name        = "${local.eks_roles[3]}"
  #    group       = "${element(aws_iam_group.eks-groups.*.name, 3)}"
  #    clusterrole = "${local.kubernetes_clusterrole_mappings[3]}"
  #  },
  #]

}
