data "helm_repository" "incubator" {
  name = "incubator"
  url  = "https://kubernetes-charts-incubator.storage.googleapis.com"
}

data "helm_repository" "ros" {
  name = "ros"
  url  = "https://rails-on-services.github.io/helm-charts"
}

data "helm_repository" "istio" {
  name = "istio"
  url  = "https://gcsweb.istio.io/gcs/istio-release/releases/${var.istio_version}/charts/"
}

data "helm_repository" "vm" {
  name = "vm"
  url  = "https://victoriametrics.github.io/helm-charts/"
}

data "helm_repository" "loki" {
  name = "loki"
  url  = "https://grafana.github.io/loki/charts"
}

data "helm_repository" "jetstack" {
  name = "jetstack"
  url  = "https://charts.jetstack.io"
}

resource "kubernetes_namespace" "extra_namespaces" {
  count = length(var.extra_namespaces)

  metadata {
    name = var.extra_namespaces[count.index]
  }
}

/*
data "http" "cert-manager-crd" {
  url = "https://raw.githubusercontent.com/jetstack/cert-manager/release-0.11/deploy/manifests/00-crds.yaml"
}

resource "k8sraw_yaml" "cert-manager-crd" {
  yaml_body = data.http.cert-manager-crd.body
}
*/

# List of CRDs required for cert-manager
resource "k8sraw_yaml" "certificaterequests" {
  yaml_body = file("${path.module}/files/cert-manager/certificaterequests.yaml")
}

resource "k8sraw_yaml" "certificates" {
  yaml_body = file("${path.module}/files/cert-manager/certificates.yaml")
}

resource "k8sraw_yaml" "challenges" {
  yaml_body = file("${path.module}/files/cert-manager/challenges.yaml")
}

resource "k8sraw_yaml" "clusterissuers" {
  yaml_body = file("${path.module}/files/cert-manager/clusterissuers.yaml")
}

resource "k8sraw_yaml" "issuers" {
  yaml_body = file("${path.module}/files/cert-manager/issuers.yaml")
}

resource "k8sraw_yaml" "orders" {
  yaml_body = file("${path.module}/files/cert-manager/orders.yaml")
}

resource "helm_release" "cert-manager" {
  depends_on = [
    kubernetes_namespace.extra_namespaces,
    k8sraw_yaml.certificaterequests,
    k8sraw_yaml.certificates,
    k8sraw_yaml.challenges,
    k8sraw_yaml.clusterissuers,
    k8sraw_yaml.issuers,
    k8sraw_yaml.orders
  ]
  name       = "cert-manager"
  repository = data.helm_repository.jetstack.metadata.0.name
  chart      = "cert-manager"
  version    = "v0.11.0"
  namespace  = var.cert_manager_namespace
  wait       = true
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

resource "helm_release" "kube-state-metrics" {
  name      = "kube-state-metrics"
  chart     = "stable/kube-state-metrics"
  namespace = "kube-system"
  wait      = true

  values = [file("${path.module}/files/kube-state-metrics.yaml")]
}

resource "kubernetes_secret" "fluentd-gcp-google-service-account" {
  count = var.enable_fluentd_gcp_logging && var.fluentd_gcp_logging_service_account_json_key != "" ? 1 : 0

  metadata {
    name      = "fluentd-gcp-google-service-account"
    namespace = "kube-system"
  }

  data = {
    "application_default_credentials.json" = var.fluentd_gcp_logging_service_account_json_key
  }
}

resource "helm_release" "cluster-logging-fluentd" {
  depends_on   = [kubernetes_secret.fluentd-gcp-google-service-account]
  count        = var.enable_fluentd_gcp_logging ? 1 : 0
  repository   = data.helm_repository.ros.metadata.0.name
  chart        = "k8s-cluster-logging"
  name         = "cluster-logging-fluentd"
  namespace    = "kube-system"
  wait         = true
  force_update = true
  version      = "0.0.9"

  values = [templatefile("${path.module}/templates/helm-fluentd-gcp.tpl", {
    cluster_name               = var.cluster_name,
    cluster_location           = var.region
    gcp_service_account_secret = var.fluentd_gcp_logging_service_account_json_key != "" ? "fluentd-gcp-google-service-account" : ""
    pull_policy                = "Always"
    }
    )
  ]

  set {
    name  = "fullnameOverride"
    value = "cluster-logging-fluentd"
  }
}

resource "helm_release" "aws-alb-ingress-controller" {
  name       = "aws-alb-ingress-controller"
  repository = data.helm_repository.incubator.metadata.0.name
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
  name       = "istio-init"
  repository = data.helm_repository.istio.metadata.0.name
  chart      = "istio-init"
  version    = var.istio_version
  namespace  = "istio-system"
  wait       = true

  force_update = true
}

resource "null_resource" "delay" {
  provisioner "local-exec" {
    command = <<EOS
for i in `seq 1 20`; do \
echo "${var.kubeconfig}" > kube_config.yaml & \
CRDS=`kubectl get crds --kubeconfig kube_config.yaml | grep 'istio.io\|certmanager.k8s.io' | wc -l`; \
echo "crds=$CRDS"; \
[ $CRDS -ge 23 ] && break || sleep 10; \
done;
rm kube_config.yaml;
EOS
  }

  depends_on = [
    helm_release.istio-init,
  ]
}

resource "helm_release" "istio" {
  depends_on = [
    helm_release.istio-init,
    null_resource.delay,
  ]
  name       = "istio"
  repository = data.helm_repository.istio.metadata.0.name
  chart      = "istio"
  version    = var.istio_version
  namespace  = "istio-system"
  wait       = true
  values     = [
    file("${path.module}/files/helm-istio.yaml"),
    jsonencode(lookup(var.helm_configuration_overrides, "istio", {}))
  ]
}

resource "helm_release" "istio-alb-ingressgateway" {
  depends_on = [helm_release.istio]
  repository = data.helm_repository.ros.metadata.0.name
  chart      = "istio-alb-ingressgateway"
  name       = "istio-alb-ingressgateway"
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

resource "kubernetes_secret" "grafana-credentials" {
  depends_on = [kubernetes_namespace.extra_namespaces]

  metadata {
    name      = "grafana-credentials"
    namespace = var.grafana_namespace
  }

  data = {
    username = var.grafana_user
    password = var.grafana_password
  }
}

resource "kubernetes_secret" "grafana-datasources" {
  count      = length(fileset(path.module, "files/grafana/datasources/*.yaml"))
  depends_on = [kubernetes_namespace.extra_namespaces]

  metadata {
    name      = "grafana-datasource-${replace(replace(basename(sort(fileset(path.module, "files/grafana/datasources/*.yaml"))[count.index]), ".yaml", ""), "_", "-")}"
    namespace = var.grafana_namespace

    labels = {
      grafana_datasource = 1
    }
  }

  data = {
    basename(sort(fileset(path.module, "files/grafana/datasources/*.yaml"))[count.index]) = file("${path.module}/${sort(fileset(path.module, "files/grafana/datasources/*.yaml"))[count.index]}")
  }
}

resource "kubernetes_config_map" "grafana-dashboards" {
  count      = length(fileset(path.module, "files/grafana/dashboards/*.json"))
  depends_on = [kubernetes_namespace.extra_namespaces]

  metadata {
    name      = "grafana-dashboard-${replace(replace(basename(sort(fileset(path.module, "files/grafana/dashboards/*.json"))[count.index]), ".json", ""), "_", "-")}"
    namespace = var.grafana_namespace

    labels = {
      grafana_dashboard = 1
    }
  }

  data = {
    basename(sort(fileset(path.module, "files/grafana/dashboards/*.json"))[count.index]) = file("${path.module}/${sort(fileset(path.module, "files/grafana/dashboards/*.json"))[count.index]}")
  }
}

resource "helm_release" "grafana-ingress" {
  depends_on = [
    kubernetes_namespace.extra_namespaces,
    helm_release.istio
  ]

  name      = "grafana-ingress"
  chart     = "${path.module}/files/grafana-ingress"
  namespace = var.grafana_namespace
  wait      = true

  values = [templatefile("${path.module}/templates/grafana/helm-grafana-ingress.tpl", {
    host     = var.grafana_host,
    endpoint = var.grafana_endpoint
    }
    )
  ]
}

resource "helm_release" "grafana" {
  depends_on = [
    kubernetes_namespace.extra_namespaces,
    kubernetes_secret.grafana-credentials,
    kubernetes_config_map.grafana-dashboards,
    kubernetes_secret.grafana-datasources
  ]

  name         = "grafana"
  chart        = "grafana"
  repository   = "stable"
  namespace    = var.grafana_namespace
  wait         = true
  force_update = true

  values = [
    templatefile("${path.module}/templates/grafana/helm-grafana.tpl", {}),
    jsonencode(lookup(var.helm_configuration_overrides, "grafana", {}))
  ]
}

resource "helm_release" "prometheus" {
  depends_on = [kubernetes_namespace.extra_namespaces]

  name         = "prometheus"
  chart        = "prometheus"
  repository   = "stable"
  namespace    = var.grafana_namespace
  wait         = true
  force_update = true

  values = [
    #templatefile("${path.module}/templates/helm-prometheus.tpl", {}),
    file("${path.module}/files/helm-prometheus.yaml"),
    jsonencode(lookup(var.helm_configuration_overrides, "prometheus", {}))
  ]
}

resource "helm_release" "loki" {
  depends_on = [kubernetes_namespace.extra_namespaces]
  name         = "loki"
  chart        = "loki"
  repository   = data.helm_repository.loki.metadata.0.name
  namespace    = var.grafana_namespace
  wait         = true
  force_update = true

  values = [file("${path.module}/files/helm-loki.yaml")]
}

resource "helm_release" "victoria-metrics" {
  depends_on = [kubernetes_namespace.extra_namespaces]
  name         = "victoria-metrics"
  chart        = "victoria-metrics-cluster"
  repository   = data.helm_repository.vm.metadata.0.name
  namespace    = var.grafana_namespace
  wait         = true
  force_update = true

  values = [templatefile("${path.module}/templates/helm-victoria-metrics.tpl", {})]

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
  depends_on = [helm_release.istio-alb-ingressgateway]
  program    = ["python", "${path.module}/files/get_alb_arn.py"]

  query = {
    config_name = "${var.cluster_name}",
    aws_profile = var.aws_profile
  }
}
