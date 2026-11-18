variable "region" {
  description = "Região onde o ambiente sobe (primário: us-east-1 | DR: us-west-2)."
  type        = string
  default     = "us-east-1"
}

variable "site" {
  description = "Papel deste ambiente: primary (produção ativa) ou dr (warm standby)."
  type        = string
  default     = "primary"

  validation {
    condition     = contains(["primary", "dr"], var.site)
    error_message = "site deve ser 'primary' ou 'dr'."
  }
}

variable "backup_region" {
  description = "Região do bucket de backup do Velero (sempre diferente da primária)."
  type        = string
  default     = "us-west-2"
}

variable "db_password" {
  description = "Senha do usuário master do RDS."
  type        = string
  sensitive   = true
}

variable "lab_role_name" {
  description = "IAM Role já existente do AWS Academy (o Lab não deixa criar Roles)."
  type        = string
  default     = "LabRole"
}

variable "install_addons" {
  description = "true = instala Argo CD e Velero (2º apply, com o cluster já de pé)."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# FinOps: tags obrigatórias. A validação barra o plan se alguma faltar.
# ---------------------------------------------------------------------------
variable "tags" {
  description = "Tags obrigatórias de FinOps aplicadas em todos os recursos."
  type        = map(string)
  default = {
    Project     = "SolidaryTech"
    Environment = "Production"
    CostCenter  = "NGO-Core"
  }

  validation {
    condition     = alltrue([for k in ["Project", "Environment", "CostCenter"] : contains(keys(var.tags), k) && length(trimspace(lookup(var.tags, k, ""))) > 0])
    error_message = "As tags Project, Environment e CostCenter são obrigatórias e não podem ser vazias."
  }
}

variable "owner" {
  description = "Responsável pelo ambiente (tag Owner)."
  type        = string
  default     = "leonardopetruncko"
}

# ---------------------------------------------------------------------------
# Rightsizing / custo (valores ajustáveis por ambiente em envs/*.tfvars)
# ---------------------------------------------------------------------------
variable "node_instance_types" {
  type    = list(string)
  default = ["t3.large"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND ou SPOT (recomendação de FinOps para ambientes não críticos)."
  type        = string
  default     = "ON_DEMAND"
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_multi_az" {
  description = "Multi-AZ no RDS (dobra o custo do banco; recomendado em produção real)."
  type        = bool
  default     = false
}

variable "db_backup_retention_days" {
  description = "Dias de backup automático do RDS (habilita PITR, base do RPO)."
  type        = number
  default     = 7
}

variable "rds_cross_region_backup" {
  description = "Replica os backups automáticos do RDS para a região de DR (RPO de minutos)."
  type        = bool
  default     = false
}

variable "rds_restore_from_backup_arn" {
  description = "Só no DR: ARN do backup replicado do primário (o scripts/dr.ps1 descobre sozinho)."
  type        = string
  default     = ""
}

variable "monthly_budget_usd" {
  description = "Limite do AWS Budget mensal. 0 = não cria (o AWS Academy bloqueia o Budgets)."
  type        = number
  default     = 0
}

variable "budget_alert_email" {
  type    = string
  default = ""
}
