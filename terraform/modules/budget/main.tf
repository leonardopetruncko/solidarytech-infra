# AWS Budget mensal filtrado pela tag Project=SolidaryTech, com alerta em 80%
# do previsto (forecast) e 100% do real. Opcional: o AWS Academy bloqueia o
# serviço Budgets, então só é criado com monthly_budget_usd > 0.

variable "limit_usd" {
  type = number
}

variable "alert_email" {
  type = string
}

resource "aws_budgets_budget" "mensal" {
  name         = "solidarytech-mensal"
  budget_type  = "COST"
  limit_amount = tostring(var.limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = ["user:Project$SolidaryTech"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
}
