variable "environment"    { type = string }
variable "s3_bucket_arn"  { type = string }
variable "sqs_queue_arn"  { type = string }
variable "sqs_dlq_arn"    { type = string }

locals {
  name = "fiap-hackaton-${var.environment}"
  tags = { Environment = var.environment, Project = "fiap-hackaton" }
}

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Upload Service role — needs S3 write + SQS publish
resource "aws_iam_role" "upload_service" {
  name               = "${local.name}-upload-service-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy" "upload_service" {
  name = "upload-service-policy"
  role = aws_iam_role.upload_service.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
        Resource = "${var.s3_bucket_arn}/uploads/*"
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage", "sqs:GetQueueAttributes"]
        Resource = var.sqs_queue_arn
      }
    ]
  })
}

# AI Processing Service role — needs S3 read + SQS consume
resource "aws_iam_role" "ai_processing" {
  name               = "${local.name}-ai-processing-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy" "ai_processing" {
  name = "ai-processing-policy"
  role = aws_iam_role.ai_processing.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${var.s3_bucket_arn}/uploads/*"
      },
      {
        Effect   = "Allow"
        Action   = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = [var.sqs_queue_arn, var.sqs_dlq_arn]
      }
    ]
  })
}

output "upload_service_role_arn" { value = aws_iam_role.upload_service.arn }
output "ai_processing_role_arn"  { value = aws_iam_role.ai_processing.arn }
