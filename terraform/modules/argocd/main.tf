# Argo CD via Helm: é o único deploy "empurrado". Daqui em diante tudo é GitOps
# (pull-based): o Argo CD lê o repositório solidarytech-gitops e sincroniza.

variable "chart_version" {
  type    = string
  default = "7.7.11"
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  set {
    name  = "configs.params.server\\.insecure"
    value = "true" # acesso por port-forward em http://localhost:8080
  }

  # Rightsizing também na plataforma.
  values = [yamlencode({
    controller = { resources = { requests = { cpu = "100m", memory = "256Mi" }, limits = { memory = "768Mi" } } }
    repoServer = { resources = { requests = { cpu = "50m", memory = "128Mi" }, limits = { memory = "512Mi" } } }
    server     = { resources = { requests = { cpu = "50m", memory = "64Mi" }, limits = { memory = "256Mi" } } }
    dex        = { enabled = false }
  })]
}
