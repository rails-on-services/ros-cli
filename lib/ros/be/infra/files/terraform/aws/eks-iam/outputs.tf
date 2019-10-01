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
      rolearn  = element(aws_iam_role.eks-roles.*.arn, i)
      username = "aws:{{AccountID}}:session:{{SessionName}}"
      groups   = [element(aws_iam_group.eks-groups.*.name, i)]
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
}