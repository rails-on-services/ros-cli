resource "null_resource" "helm-repository-incubator" {
  triggers = {
    always = timestamp()
  }

  provisioner "local-exec" {
    command = "helm repo add incubator https://kubernetes-charts-incubator.storage.googleapis.com"
  }
}

#resource "null_resource" "helm-repository-kube-eagle" {
#  triggers = {
#    always = timestamp()
#  }
#
#  provisioner "local-exec" {
#    command = "helm repo add kube-eagle https://raw.githubusercontent.com/google-cloud-tools/kube-eagle-helm-chart/master"
#  }
#}

resource "null_resource" "helm-repository-istio" {
  triggers = {
    always = timestamp()
  }

  provisioner "local-exec" {
    command = "helm repo add istio https://gcsweb.istio.io/gcs/istio-release/releases/${var.istio_version}/charts/"
  }
}

resource "kubernetes_namespace" "extra_namespaces" {
  count = length(var.extra_namespaces)

  metadata {
    name = var.extra_namespaces[count.index]
  }
}

resource "helm_release" "cluster-autoscaler" {
  name      = "cluster-autoscaler"
  chart     = "stable/cluster-autoscaler"
  namespace = "kube-system"
  wait      = true

  values = [templatefile("${path.module}/templates/helm-cluster-autoscaler.tpl", {
    aws_region   = var.region,
    cluster_name = var.cluster_name
    }
    )
  ]
}

resource "helm_release" "metrics-server" {
  name      = "metrics-server"
  chart     = "stable/metrics-server"
  namespace = "kube-system"
  wait      = true

  values = [file("${path.module}/files/helm-metrics-server.yaml")]
}

resource "kubernetes_secret" "fluentd-gcp-google-service-account" {
  count = var.enable_fluentd_gcp_logging && fileexists("${path.module}/files/gcp_fluentd_logging_credentials.json") ? 1 : 0

  metadata {
    name      = "fluentd-gcp-google-service-account"
    namespace = "kube-system"
  }

  data = {
    "application_default_credentials.json" = file("${path.module}/files/gcp_fluentd_logging_credentials.json")
  }
}

resource "helm_release" "fluentd-gcp" {
  depends_on = [kubernetes_secret.fluentd-gcp-google-service-account]
  count      = var.enable_fluentd_gcp_logging && fileexists("${path.module}/files/gcp_fluentd_logging_credentials.json") ? 1 : 0
  chart      = "${path.module}/files/fluentd"
  name       = "fluentd-gcp"
  namespace  = "kube-system"
  wait       = true

  values = [templatefile("${path.module}/templates/helm-fluentd-gcp.tpl", {
    cluster_name     = var.cluster_name,
    cluster_location = var.region
    }
    )
  ]
}

resource "helm_release" "aws-alb-ingress-controller" {
  depends_on = [null_resource.helm-repository-incubator]
  name       = "aws-alb-ingress-controller"
  repository = "incubator"
  chart      = "aws-alb-ingress-controller"
  namespace  = "kube-system"
  wait       = true

  values = [templatefile("${path.module}/templates/helm-aws-alb-ingress-controller.tpl", {
    cluster_name = var.cluster_name,
    aws_region   = var.region,
    vpc_id       = var.vpc_id
    }
    )
  ]
}

resource "helm_release" "external-dns" {
  count     = var.enable_external_dns ? 1 : 0
  name      = "external-dns"
  chart     = "stable/external-dns"
  namespace = "kube-system"
  wait      = true
  values = [templatefile("${path.module}/templates/helm-external-dns.tpl", {
    aws_region    = var.region,
    zoneType      = var.external_dns_route53_zone_type,
    domainFilters = jsonencode(var.external_dns_domainFilters),
    zoneIdFilters = jsonencode(var.external_dns_zoneIdFilters)
    }
    )
  ]

}

resource "kubernetes_cluster_role_binding" "this" {
  count = length(var.clusterrolebindings)

  metadata {
    name = var.clusterrolebindings[count.index]["name"]
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = var.clusterrolebindings[count.index]["clusterrole"]
  }

  subject {
    kind      = "Group"
    name      = var.clusterrolebindings[count.index]["group"]
    api_group = "rbac.authorization.k8s.io"

    # no need to limit to only one namespace
    namespace = ""
  }
}

resource "helm_release" "istio-init" {
  depends_on = [null_resource.helm-repository-istio]
  name       = "istio-init"
  repository = "istio"
  chart      = "istio-init"
  namespace  = "istio-system"
  wait       = true

  force_update = true
}

resource "null_resource" "delay" {
  provisioner "local-exec" {
    command = <<EOS
for i in `seq 1 20`; do \
echo "${var.kubeconfig}" > ~/.kube/"${var.cluster_name}"_config.yaml & \
CRDS=`kubectl get crds --kubeconfig ~/.kube/"${var.cluster_name}"_config.yaml | grep 'istio.io\|certmanager.k8s.io' | wc -l`; \
echo "crds=$CRDS"; \
[ $CRDS -ge 23 ] && break || sleep 10; \
done; 
EOS
  }

  depends_on = [
    helm_release.istio-init,
  ]
}

resource "helm_release" "istio" {
  depends_on = [
    null_resource.helm-repository-istio,
    helm_release.istio-init,
    null_resource.delay,
  ]
  name       = "istio"
  repository = "istio"
  chart      = "istio"
  version    = var.istio_version
  namespace  = "istio-system"
  wait       = true
  values     = [file("${path.module}/files/helm-istio.yaml")]
}

resource "helm_release" "istio-alb-ingressgateway" {
  depends_on = [helm_release.istio]
  name       = "istio-alb-ingressgateway"
  chart      = "${path.module}/files/istio-alb-ingressgateway"
  namespace  = "istio-system"
  wait       = true

  set {
    name  = "ingress.annotations.alb\\.ingress\\.kubernetes\\.io/certificate-arn"
    value = var.istio_ingressgateway_alb_cert_arn
  }

  lifecycle {
    create_before_destroy = false
  }
}

# This is to create an extra kubernetes clusterrole for developers
resource "kubernetes_cluster_role" "developer" {
  metadata {
    name = "developer"
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["get", "list", "watch"]
  }

  # allow port-forward
  rule {
    api_groups = [""]
    resources  = ["pods/portforward"]
    verbs      = ["get", "list", "create"]
  }

  # allow exec into pod
  rule {
    api_groups = [""]
    resources  = ["pods/exec"]
    verbs      = ["create"]
  }
}

data "external" "alb_arn" {
  depends_on = ["helm_release.istio-alb-ingressgateway"]
  program    = ["python", "${path.module}/files/get_alb_arn.py"]

  query = {
    config_name = "${var.cluster_name}_config.yaml",
    aws_profile = var.aws_profile
  }
}