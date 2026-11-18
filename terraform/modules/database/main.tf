# Dados da SolidaryTech.
#
# FinOps: UMA instância RDS PostgreSQL com dois bancos lógicos (ngo_db e
# donation_db), em vez de uma instância por serviço. Os bancos são criados pelo
# Job de init de cada serviço (GitOps), não aqui.
#
# DR: backup automático com retenção (habilita Point-in-Time Recovery = RPO de
# ~5 min) e DynamoDB com PITR (restauração a qualquer segundo dos últimos 35 dias).

variable "name" {
  type = string
}

variable "db_subnet_group_name" {
  type = string
}

variable "data_security_group_id" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "db_instance_class" {
  type = string
}

variable "db_multi_az" {
  type = bool
}

variable "backup_retention_days" {
  type = number
}

variable "restore_from_backup_arn" {
  description = "DR: ARN do backup automático replicado do primário. Vazio = banco novo."
  type        = string
  default     = ""
}

resource "aws_db_instance" "postgres" {
  identifier     = "${var.name}-postgres"
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.db_instance_class

  allocated_storage     = 20
  max_allocated_storage = 50 # autoscaling de disco: paga só o que usar
  storage_type          = "gp3"
  storage_encrypted     = true

  username = var.restore_from_backup_arn == "" ? "dbadmin" : null # no restore o usuário vem do backup
  password = var.db_password

  db_subnet_group_name   = var.db_subnet_group_name
  vpc_security_group_ids = [var.data_security_group_id]
  publicly_accessible    = false
  multi_az               = var.db_multi_az

  backup_retention_period = var.backup_retention_days
  backup_window           = "06:00-07:00" # 03h-04h em Brasília: menor volume de doações
  maintenance_window      = "sun:07:00-sun:08:00"
  copy_tags_to_snapshot   = true

  skip_final_snapshot = true # ambiente de laboratório: destruído ao fim de cada sessão
  apply_immediately   = true

  # DR: sobe o banco já com os dados do primário (último instante restaurável do
  # backup replicado em us-west-2). É isso que garante o RPO de minutos.
  dynamic "restore_to_point_in_time" {
    for_each = var.restore_from_backup_arn != "" ? [1] : []
    content {
      source_db_instance_automated_backups_arn = var.restore_from_backup_arn
      use_latest_restorable_time               = true
    }
  }

  tags = {
    Name    = "${var.name}-postgres"
    Service = "ngo-service,donation-service"
  }
}

resource "aws_dynamodb_table" "volunteers" {
  name         = "SolidaryTechVolunteers"
  billing_mode = "PAY_PER_REQUEST" # FinOps: sem capacidade ociosa; paga por requisição
  hash_key     = "volunteer_id"

  attribute {
    name = "volunteer_id"
    type = "S"
  }

  attribute {
    name = "ngo_id"
    type = "N"
  }

  # FinOps + latência: "voluntários da ONG X" vira Query no índice em vez de Scan
  # (o Scan lê e cobra a tabela inteira a cada consulta).
  global_secondary_index {
    name            = "ngo_id-index"
    hash_key        = "ngo_id"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name    = "SolidaryTechVolunteers"
    Service = "volunteer-service"
  }
}

output "rds_arn" {
  value = aws_db_instance.postgres.arn
}

output "rds_endpoint" {
  value = aws_db_instance.postgres.address
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.volunteers.name
}
