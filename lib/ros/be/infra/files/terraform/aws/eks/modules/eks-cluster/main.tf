
#data "terraform_remote_state" "eks-vpc" {
#  backend = "local"
#}

resource "aws_security_group" "eks-cluster" {
  name        = join("-", [var.cluster_name, "eks-cluster"])  #join("-", ["stack", terraform.workspace, "eks-cluster"])
  description = "Cluster communication with worker nodes"
  vpc_id      = var.vpc_id #data.terraform_remote_state.eks-vpc.outputs.vpc.vpc_id #var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

## OPTIONAL: Allow inbound traffic from internet to the Kubernetes.
resource "aws_security_group_rule" "eks-cluster-ingress-internet-https" {
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow workstations to communicate with the cluster API Server"
  from_port         = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.eks-cluster.id
  to_port           = 443
  type              = "ingress"
}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 5.1.0"
  cluster_name    = var.cluster_name
  subnets         = concat(var.public_subnets, var.private_subnets) #concat(data.terraform_remote_state.eks-vpc.outputs.vpc.public_subnets, data.terraform_remote_state.eks-vpc.outputs.vpc.private_subnets)
  vpc_id          = var.vpc_id #data.terraform_remote_state.eks-vpc.outputs.vpc.vpc_id #var.vpc_id

  cluster_create_security_group   = "false"
  cluster_endpoint_private_access = "true"
  cluster_endpoint_public_access  = "true"
  cluster_security_group_id       = aws_security_group.eks-cluster.id
  worker_ami_name_filter          = var.eks_worker_ami_name_filter
  cluster_enabled_log_types       = var.eks_cluster_enabled_log_types

  manage_aws_auth    = "true"
  write_kubeconfig   = "true"
  config_output_path = "./"

  workers_group_defaults = {
    subnets                       = var.private_subnets #data.terraform_remote_state.eks-vpc.outputs.vpc.private_subnets
    additional_security_group_ids = var.default_security_group_id #data.terraform_remote_state.eks-vpc.outputs.vpc.default_security_group_id #module.eks-vpc.default_security_group_id #
  }

  kubeconfig_aws_authenticator_env_variables = {
    AWS_PROFILE = var.aws_profile
  }

  # using launch configuration
  worker_groups = [merge(local.worker_groups, var.eks_worker_groups)]

  # not using launch template
  worker_groups_launch_template = []

  map_users       = var.eks_map_users
  map_roles       = var.eks_map_roles

  tags = var.tags
}

## attach iam policy to allow aws alb ingress controller
resource "aws_iam_policy" "eks-worker-alb-ingress-controller" {
  name_prefix = "eks-worker-ingress-controller-${var.cluster_name}"
  description = "EKS worker node alb ingress controller policy for cluster ${var.cluster_name}"
  policy = file(
    "${path.module}/files/aws-alb-ingress-controller-iam-policy.json",
  )
}

resource "aws_iam_role_policy_attachment" "eks-worker-alb-ingress-controller" {
  policy_arn = aws_iam_policy.eks-worker-alb-ingress-controller.arn
  role       = module.eks.worker_iam_role_name
}

## attach iam policy to allow external-dns
resource "aws_iam_policy" "eks-worker-external-dns" {
  name_prefix = "eks-worker-external-dns-${var.cluster_name}"
  description = "EKS worker node external dns policy for cluster ${var.cluster_name}"
  policy      = file("${path.module}/files/aws-external-dns-iam-policy.json")
}

#resource "aws_iam_policy" "eks-worker-extra" {
#  count       = var.extra_eks_iam_policy != "" ? 1 : 0
#  name_prefix = "eks-worker-extra-${var.cluster_name}"
#  description = "Extra IAM permissions for eks worker"
#  policy      = var.extra_eks_iam_policy
#}
#
#resource "aws_iam_role_policy_attachment" "eks-worker-extra" {
#  count      = var.extra_eks_iam_policy != "" ? 1 : 0
#  policy_arn = aws_iam_policy.eks-worker-extra[0].arn
#  role       = module.eks.worker_iam_role_name
#}

resource "aws_iam_role_policy_attachment" "eks-worker-external-dns" {
  policy_arn = aws_iam_policy.eks-worker-external-dns.arn
  role       = module.eks.worker_iam_role_name
}

resource "null_resource" "k8s-tiller-rbac" {
  depends_on = [module.eks]

  provisioner "local-exec" {
    working_dir = path.module

    command = <<EOS
for i in `seq 1 10`; do \
echo "${module.eks.kubeconfig}" > kube_config.yaml & \
kubectl apply -f files/tiller-rbac.yaml --kubeconfig kube_config.yaml && break || \
sleep 10; \
done; \
rm kube_config.yaml;
EOS

  }

  triggers = {
    kube_config_rendered = module.eks.kubeconfig
  }
}

