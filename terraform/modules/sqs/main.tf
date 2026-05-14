variable "environment" { type = string }

locals {
  name = "fiap-hackaton-${var.environment}"
  tags = { Environment = var.environment, Project = "fiap-hackaton" }
}

resource "aws_sqs_queue" "dlq" {
  name                      = "${local.name}-diagram-analysis-dlq"
  message_retention_seconds = 86400
  tags                      = local.tags
}

resource "aws_sqs_queue" "main" {
  name                       = "${local.name}-diagram-analysis-queue"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 345600

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })

  tags = local.tags
}

output "queue_url" { value = aws_sqs_queue.main.url }
output "queue_arn" { value = aws_sqs_queue.main.arn }
output "dlq_arn"   { value = aws_sqs_queue.dlq.arn }
