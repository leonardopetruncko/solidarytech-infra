variable "services" {
  type    = list(string)
  default = ["ngo-service", "donation-service", "volunteer-service"]
}

resource "aws_ecr_repository" "services" {
  for_each = toset(var.services)

  name = each.key
  # A tag já é o commit (v1.0.0-<sha>); MUTABLE só para permitir re-rodar o mesmo
  # commit pelo workflow_dispatch sem erro de "tag already exists".
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Service = each.key }
}

# FinOps: guarda só as 10 últimas imagens (armazenamento do ECR é cobrado por GB).
resource "aws_ecr_lifecycle_policy" "keep_last_10" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Mantem as 10 imagens mais recentes"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

output "repository_urls" {
  value = { for k, v in aws_ecr_repository.services : k => v.repository_url }
}
