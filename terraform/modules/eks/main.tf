# EKS + node group gerenciado. Cluster e nós usam a LabRole (o AWS Academy não
# deixa criar IAM Roles).

variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  type    = string
  default = "1.34"
}

variable "lab_role_arn" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "tags" {
  description = "Tags de FinOps propagadas às instâncias e discos dos nós (launch template)."
  type        = map(string)
}

variable "node_instance_types" {
  type = list(string)
}

variable "node_capacity_type" {
  type = string
}

variable "node_desired_size" {
  type = number
}

variable "node_min_size" {
  type = number
}

variable "node_max_size" {
  type = number
}

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = var.lab_role_arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = concat(var.public_subnet_ids, var.private_subnet_ids)
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  # Logs do control plane desligados de propósito (FinOps: CloudWatch cobra por GB).
  enabled_cluster_log_types = []
}

# ---------------------------------------------------------------------------
# Launch template dos nós:
#  1. FinOps: o default_tags do provider NÃO chega nas instâncias e discos que o
#     Auto Scaling cria. O tag_specifications resolve isso (custo 100% tagueado).
#  2. IMDSv2 com hop limit 2: os pods conseguem usar a LabRole do nó para falar
#     com SQS, DynamoDB e S3 (Velero) sem chave estática dentro do cluster.
# ---------------------------------------------------------------------------
resource "aws_launch_template" "nodes" {
  name_prefix = "${var.cluster_name}-nodes-"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 30
      volume_type           = "gp3" # gp3: ~20% mais barato que gp2 e com IOPS base maior
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.cluster_name}-node" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(var.tags, { Name = "${var.cluster_name}-node-disk" })
  }

  tag_specifications {
    resource_type = "network-interface"
    tags          = var.tags
  }
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-nodes"
  node_role_arn   = var.lab_role_arn
  subnet_ids      = var.private_subnet_ids
  version         = var.kubernetes_version

  instance_types = var.node_instance_types
  capacity_type  = var.node_capacity_type

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    "solidarytech.org/capacity" = lower(var.node_capacity_type)
  }
}

# metrics-server: base do HPA e do rightsizing (kubectl top / métricas de uso).
resource "aws_eks_addon" "metrics_server" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "metrics-server"

  depends_on = [aws_eks_node_group.main]
}

output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority_data" {
  value = aws_eks_cluster.main.certificate_authority[0].data
}

# SG que o EKS cria e anexa aos nós: é a origem real do tráfego dos pods.
output "cluster_security_group_id" {
  value = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}
