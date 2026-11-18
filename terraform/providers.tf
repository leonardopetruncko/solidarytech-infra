terraform {
  required_version = ">= 1.10.0" # use_lockfile (lock nativo do S3) exige 1.10+

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16"
    }
  }

  # ---------------------------------------------------------------------------
  # Backend remoto com configuração parcial: o nome do bucket depende do ID da
  # conta (muda a cada conta do AWS Academy), então ele entra no init:
  #   terraform init -backend-config="bucket=solidarytech-tfstate-<ACCOUNT_ID>"
  # O scripts/subir.ps1 faz isso sozinho. Cada workspace (default = primário,
  # dr = warm standby) tem o próprio state dentro do mesmo bucket (env:/dr/...).
  # ---------------------------------------------------------------------------
  backend "s3" {
    key          = "solidarytech/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

# ---------------------------------------------------------------------------
# FinOps: política de tags aplicada em TODOS os recursos que o provider cria.
# Os recursos que a AWS cria "por fora" do provider (instâncias e discos dos
# nós do EKS) recebem as mesmas tags pelo launch template (modules/eks).
# ---------------------------------------------------------------------------
provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags_obrigatorias
  }
}

# Região do bucket de backup (Velero). Fica FORA da região primária de propósito:
# se us-east-1 cair, o backup continua acessível em us-west-2.
provider "aws" {
  alias  = "backup"
  region = var.backup_region

  default_tags {
    tags = local.tags_obrigatorias
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}
