data "aws_caller_identity" "current" {}

data "aws_iam_role" "lab_role" {
  name = var.lab_role_name
}

locals {
  name       = var.site == "primary" ? "solidarytech" : "solidarytech-dr"
  account_id = data.aws_caller_identity.current.account_id

  # Tags de FinOps (obrigatórias) + rastreabilidade.
  tags_obrigatorias = merge(var.tags, {
    Owner     = var.owner
    ManagedBy = "Terraform"
    Site      = var.site
  })

  # Bucket do Velero: um só, na região de backup, usado pelo primário E pelo DR
  # (é assim que o DR restaura o que o primário salvou).
  velero_bucket = "solidarytech-velero-${local.account_id}"
}

module "network" {
  source = "./modules/network"
  name   = local.name
}

module "eks" {
  source = "./modules/eks"

  cluster_name        = "${local.name}-eks"
  lab_role_arn        = data.aws_iam_role.lab_role.arn
  public_subnet_ids   = module.network.public_subnet_ids
  private_subnet_ids  = module.network.private_subnet_ids
  tags                = local.tags_obrigatorias
  node_instance_types = var.node_instance_types
  node_capacity_type  = var.node_capacity_type
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
}

module "database" {
  source = "./modules/database"

  name                   = local.name
  db_subnet_group_name   = module.network.db_subnet_group_name
  data_security_group_id = module.network.data_security_group_id
  db_password            = var.db_password
  db_instance_class      = var.db_instance_class
  db_multi_az            = var.db_multi_az
  backup_retention_days  = var.db_backup_retention_days

  restore_from_backup_arn = var.rds_restore_from_backup_arn
}

# DR dos DADOS das doações: replica os backups automáticos (e o log de transações)
# do RDS para a região de DR. Permite subir o banco em us-west-2 com RPO de minutos.
resource "aws_db_instance_automated_backups_replication" "dr" {
  count    = var.site == "primary" && var.rds_cross_region_backup ? 1 : 0
  provider = aws.backup

  source_db_instance_arn = module.database.rds_arn
  retention_period       = 7
  kms_key_id             = aws_kms_key.rds_dr[0].arn # banco criptografado: a cópia exige chave na região de destino
}

# Chave KMS na região de DR para criptografar os backups replicados (~US$ 1/mês).
resource "aws_kms_key" "rds_dr" {
  count    = var.site == "primary" && var.rds_cross_region_backup ? 1 : 0
  provider = aws.backup

  description             = "SolidaryTech - backups do RDS replicados para o DR"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

module "messaging" {
  source = "./modules/messaging"
  name   = local.name
}

# Os repositórios ECR são do primário; o DR puxa as imagens de lá
# (em produção real: ECR replication para a região de DR).
module "ecr" {
  source = "./modules/ecr"
  count  = var.site == "primary" ? 1 : 0
}

module "backup" {
  source = "./modules/backup"
  count  = var.site == "primary" ? 1 : 0

  providers = {
    aws = aws.backup
  }

  bucket_name = local.velero_bucket
}

module "budget" {
  source = "./modules/budget"
  count  = var.monthly_budget_usd > 0 ? 1 : 0

  limit_usd   = var.monthly_budget_usd
  alert_email = var.budget_alert_email
}

# ---------------------------------------------------------------------------
# Add-ons do cluster (2º apply, -var install_addons=true): Argo CD + Velero.
# Ficam no Terraform (e não no GitOps) porque dependem de dados da conta
# (bucket, região) e são o "bootstrap" que liga o GitOps.
# ---------------------------------------------------------------------------
module "argocd" {
  source = "./modules/argocd"
  count  = var.install_addons ? 1 : 0

  depends_on = [module.eks]
}

module "velero" {
  source = "./modules/velero"
  count  = var.install_addons ? 1 : 0

  bucket_name   = local.velero_bucket
  bucket_region = var.backup_region
  cluster_name  = module.eks.cluster_name
  # O DR só restaura: não agenda backup próprio (evita sobrescrever o do primário).
  create_schedule = var.site == "primary"

  depends_on = [module.eks, module.backup]
}

# ---------------------------------------------------------------------------
# Acesso dos pods ao RDS: os nós usam a SG que o próprio EKS cria
# (eks-cluster-sg-*), então é ela que precisa ser liberada na porta 5432.
# ---------------------------------------------------------------------------
resource "aws_security_group_rule" "data_postgres_from_eks_nodes" {
  type                     = "ingress"
  description              = "PostgreSQL a partir dos nos do EKS"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.network.data_security_group_id
  source_security_group_id = module.eks.cluster_security_group_id
}
