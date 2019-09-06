data "aws_caller_identity" "current" {}

resource "aws_iam_role" "eks-roles" {
  count = length(local.eks_roles)
  name  = element(local.eks_roles, count.index)

  description = "Managed by Terraform"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      },
      "Action": "sts:AssumeRole",
      "Condition": {}
    }
  ]
}
EOF
}

resource "aws_iam_group" "eks-groups" {
  count = length(local.eks_groups)
  name  = element(local.eks_groups, count.index)
}

resource "aws_iam_group_policy" "eks-group-policy" {
  count = length(local.eks_groups)

  name = "allow_assume_role_${local.eks_roles[count.index]}"

  group = element(aws_iam_group.eks-groups.*.id, count.index)

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sts:AssumeRole"
      ],
      "Resource": [
        "${element(aws_iam_role.eks-roles.*.arn, count.index)}"
      ]
    }
  ]
}
EOF
}