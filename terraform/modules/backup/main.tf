# Bucket de backup do Velero, em OUTRA região (cross-region backup).
# Se a região primária cair, o estado do cluster continua salvo aqui.
#
# O bucket em si é criado pelo scripts/subir.ps1 (AWS CLI): no AWS Academy uma SCP nega
# s3:GetBucketObjectLockConfiguration, que o recurso aws_s3_bucket sempre lê. Toda a
# CONFIGURAÇÃO do bucket (versionamento, criptografia, bloqueio público e ciclo de vida)
# continua aqui, como código.

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

variable "bucket_name" {
  type = string
}

resource "aws_s3_bucket_versioning" "velero" {
  bucket = var.bucket_name
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "velero" {
  bucket = var.bucket_name
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "velero" {
  bucket                  = var.bucket_name
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# FinOps: backups antigos vão para uma classe mais barata e expiram.
resource "aws_s3_bucket_lifecycle_configuration" "velero" {
  bucket = var.bucket_name

  rule {
    id     = "backups-velero"
    status = "Enabled"
    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.velero]
}

output "bucket_name" {
  value = var.bucket_name
}
