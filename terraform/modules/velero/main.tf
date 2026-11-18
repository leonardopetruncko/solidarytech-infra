# Velero (DR - Opção A): backup do estado do cluster para o bucket S3 da outra
# região. Usa a LabRole do nó (IMDS) para acessar o S3, então nenhuma chave fica
# guardada no cluster.
#
# O AWS Academy não tem o driver EBS CSI (não há volumes persistentes), então o
# backup é dos manifestos/recursos do Kubernetes. Os DADOS ficam protegidos pelo
# backup nativo do RDS (PITR) e do DynamoDB (PITR) - ver docs/pcn.md.

variable "bucket_name" {
  type = string
}

variable "bucket_region" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "create_schedule" {
  type = bool
}

variable "chart_version" {
  type    = string
  default = "12.2.5" # Velero 1.18
}

locals {
  todos_os_schedules = {
    # A cada 15 min: RPO do estado do cluster <= 15 min.
    solidarytech-15min = {
      schedule = "*/15 * * * *"
      template = {
        ttl                = "72h"
        includedNamespaces = ["solidarytech", "observability"]
        snapshotVolumes    = false
      }
    }
    # Diário completo (inclui argocd), guardado por 30 dias.
    cluster-diario = {
      schedule = "0 6 * * *"
      template = {
        ttl                = "720h"
        includedNamespaces = ["*"]
        excludedNamespaces = ["kube-system", "kube-public", "kube-node-lease", "velero"]
        snapshotVolumes    = false
      }
    }
  }
  schedules = { for k, v in local.todos_os_schedules : k => v if var.create_schedule }
}

resource "helm_release" "velero" {
  name             = "velero"
  repository       = "https://vmware-tanzu.github.io/helm-charts"
  chart            = "velero"
  version          = var.chart_version
  namespace        = "velero"
  create_namespace = true

  values = [yamlencode({
    initContainers = [{
      name            = "velero-plugin-for-aws"
      image           = "velero/velero-plugin-for-aws:v1.14.4"
      imagePullPolicy = "IfNotPresent"
      volumeMounts    = [{ mountPath = "/target", name = "plugins" }]
    }]

    credentials      = { useSecret = false } # usa a LabRole via IMDS
    snapshotsEnabled = false
    deployNodeAgent  = false

    configuration = {
      backupStorageLocation = [{
        name     = "default"
        provider = "aws"
        bucket   = var.bucket_name
        prefix   = "clusters"
        default  = true
        # No DR o bucket é só leitura: restaura o backup do primário sem risco de sobrescrever.
        accessMode = var.create_schedule ? "ReadWrite" : "ReadOnly"
        config     = { region = var.bucket_region }
      }]
    }

    schedules = local.schedules

    resources = {
      requests = { cpu = "50m", memory = "128Mi" }
      limits   = { memory = "512Mi" }
    }

    labels = { "solidarytech.org/cluster" = var.cluster_name }
  })]
}
