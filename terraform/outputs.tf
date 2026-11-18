output "region" {
  value = var.region
}

output "site" {
  value = var.site
}

output "account_id" {
  value = local.account_id
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "rds_endpoint" {
  value = module.database.rds_endpoint
}

output "db_password" {
  value     = var.db_password
  sensitive = true
}

output "dynamodb_table_name" {
  value = module.database.dynamodb_table_name
}

output "sqs_url" {
  value = module.messaging.queue_url
}

output "ecr_registry" {
  value = "${local.account_id}.dkr.ecr.us-east-1.amazonaws.com"
}

output "velero_bucket" {
  value = local.velero_bucket
}

output "tags_obrigatorias" {
  description = "Tags de FinOps aplicadas em todos os recursos."
  value       = local.tags_obrigatorias
}
