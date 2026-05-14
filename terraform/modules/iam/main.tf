variable "environment"    { type = string }
variable "s3_bucket_arn"  { type = string }
variable "sqs_queue_arn"  { type = string }
variable "sqs_dlq_arn"    { type = string }

locals {
  name = "fiap-hackaton-${var.environment}"
  tags = { Environment = var.environment, Project = "fiap-hackaton" }
}

# AWS Academy restricts iam:CreateRole.
# Use the pre-existing LabRole for all ECS task roles.
data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

output "upload_service_role_arn" { value = data.aws_iam_role.lab_role.arn }
output "ai_processing_role_arn"  { value = data.aws_iam_role.lab_role.arn }
