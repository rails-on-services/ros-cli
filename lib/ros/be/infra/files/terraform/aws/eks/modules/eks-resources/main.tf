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

data "template_file" "cluster-autoscaler-value" {
  template = file("${path.module}/templates/helm-cluster-autoscaler.tpl")

  vars = {
    aws_region   = var.region
    cluster_name = var.cluster_name
  }
}

resource "helm_release" "cluster-autoscaler" {
  name      = "cluster-autoscaler"
  chart     = "stable/cluster-autoscaler"
  namespace = "kube-system"
  wait      = true

  values = [data.template_file.cluster-autoscaler-value.rendered]
}

resource "helm_release" "metrics-server" {
  name      = "metrics-server"
  chart     = "stable/metrics-server"
  namespace = "kube-system"
  wait      = true

  values = [file("${path.module}/files/helm-metrics-server.yaml")]
}

#resource "helm_release" "kube-eagle" {
#  depends_on = [null_resource.helm-repository-kube-eagle]
#  repository = "kube-eagle"
#  chart      = "kube-eagle"
#  name       = "kube-eagle"
#  namespace  = "monitor"
#  wait       = true
#
#  values = [file("${path.module}/files/helm-kube-eagle.yaml")]
#}

#resource "kubernetes_secret" "fluentd-gcp-google-service-account" {
#  count = var.enable_fluentd_gcp_logging ? 1 : 0
#
#  metadata {
#    name      = "fluentd-gcp-google-service-account"
#    namespace = "kube-system"
#  }
#
#  data = {
#    "application_default_credentials.json" = file(var.fluentd_gcp_logging_service_account_json_key_path)
#  }
#}

#data "template_file" "fluentd-gcp-value" {
#  template = file("${path.module}/templates/helm-fluentd-gcp.tpl")
#
#  vars = {
#    cluster_name     = var.cluster_name
#    cluster_location = var.region
#  }
#}
#
#resource "helm_release" "fluentd-gcp" {
#  depends_on = [
#    kubernetes_secret.fluentd-gcp-google-service-account,
#    ]
#  count      = var.enable_fluentd_gcp_logging ? 1 : 0
#  chart      = "./files/fluentd-gcp"
#  name       = "fluentd-gcp"
#  namespace  = "kube-system"
#  wait       = true
#
#  values = [data.template_file.fluentd-gcp-value.rendered]
#}

data "template_file" "aws-alb-ingress-controller-value" {
  template = file(
    "${path.module}/templates/helm-aws-alb-ingress-controller.tpl",
  )

  vars = {
    cluster_name = var.cluster_name
  }
}

resource "helm_release" "aws-alb-ingress-controller" {
  depends_on = [null_resource.helm-repository-incubator]
  name       = "aws-alb-ingress-controller"
  repository = "incubator"
  chart      = "aws-alb-ingress-controller"
  namespace  = "kube-system"
  wait       = true

  values = [data.template_file.aws-alb-ingress-controller-value.rendered]
}

data "template_file" "external-dns-value" {
  template = file("${path.module}/templates/helm-external-dns.tpl")

  vars = {
    aws_region    = var.region
    zoneType      = var.external_dns_route53_zone_type
    domainFilters = jsonencode(var.external_dns_domainFilters)
    zoneIdFilters = jsonencode(var.external_dns_zoneIdFilters)
  }
}

#resource "helm_release" "external-dns" {
#  count     = var.enable_external_dns ? 1 : 0
#  name      = "external-dns"
#  chart     = "stable/external-dns"
#  namespace = "kube-system"
#  wait      = true
#  values    = [data.template_file.external-dns-value.rendered]
#}

# create external services
#resource "kubernetes_service" "external_services" {
#  count = length(var.k8s_mapping_external_services)
#
#  depends_on = [kubernetes_namespace.extra_namespaces]
#
#  metadata {
#    name = var.k8s_mapping_external_services[count.index]["name"]
#    namespace = lookup(
#      var.k8s_mapping_external_services[count.index],
#      "namespace",
#      "default",
#    )
#  }
#
#  spec {
#    external_name = var.k8s_mapping_external_services[count.index]["externalName"]
#    type          = "ExternalName"
#  }
#}

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
  count      = var.enable_istio ? 1 : 0
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
  count = var.enable_istio ? 1 : 0
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

#resource "helm_release" "istio-alb-ingressgateway" {
#  count      = var.enable_istio && var.istio_ingressgateway_alb_cert_arn != "" ? 1 : 0
#  depends_on = [helm_release.istio]
#  name       = "istio-alb-ingressgateway"
#  chart      = "./files/istio-alb-ingressgateway"
#  namespace  = "istio-system"
#  wait       = true
#
#  set {
#    name  = "ingress.annotations.alb\\.ingress\\.kubernetes\\.io/certificate-arn"
#    value = var.istio_ingressgateway_alb_cert_arn
#  }
#
#  lifecycle {
#    create_before_destroy = false
#  }
#}

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