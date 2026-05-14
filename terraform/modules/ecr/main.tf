variable "environment" { type = string }

locals {
  name = "fiap-hackaton-${var.environment}"
  tags = { Environment = var.environment, Project = "fiap-hackaton" }

  services = ["upload-service", "ai-processing-service", "report-service", "api-gateway"]
}

resource "aws_ecr_repository" "services" {
  for_each             = toset(local.services)
  name                 = "${local.name}/${each.value}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration { scan_on_push = true }

  tags = local.tags
}

resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

output "upload_service_repo_url"    { value = aws_ecr_repository.services["upload-service"].repository_url }
output "ai_processing_repo_url"     { value = aws_ecr_repository.services["ai-processing-service"].repository_url }
output "report_service_repo_url"    { value = aws_ecr_repository.services["report-service"].repository_url }
output "api_gateway_repo_url"       { value = aws_ecr_repository.services["api-gateway"].repository_url }
