# Fila de eventos de doação (publicada pelo donation-service) + DLQ.

variable "name" {
  type = string
}

resource "aws_sqs_queue" "donations_dlq" {
  name                      = "solidary-donations-dlq"
  message_retention_seconds = 1209600 # 14 dias para investigar mensagens com falha
  sqs_managed_sse_enabled   = true

  tags = { Service = "donation-service" }
}

resource "aws_sqs_queue" "donations" {
  name                       = "solidary-donations"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 345600 # 4 dias
  receive_wait_time_seconds  = 20     # long polling: menos requisições vazias = menor custo
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.donations_dlq.arn
    maxReceiveCount     = 5
  })

  tags = { Service = "donation-service" }
}

output "queue_url" {
  value = aws_sqs_queue.donations.url
}
