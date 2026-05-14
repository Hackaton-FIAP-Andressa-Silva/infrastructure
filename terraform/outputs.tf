output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.ecs.alb_dns_name
}

output "s3_bucket_name" {
  description = "S3 bucket for architecture diagrams"
  value       = module.s3.bucket_name
}

output "sqs_queue_url" {
  description = "SQS queue URL for diagram analysis jobs"
  value       = module.sqs.queue_url
}

output "ecr_repositories" {
  description = "ECR repository URLs"
  value = {
    upload_service    = module.ecr.upload_service_repo_url
    ai_processing     = module.ecr.ai_processing_repo_url
    report_service    = module.ecr.report_service_repo_url
    api_gateway       = module.ecr.api_gateway_repo_url
  }
}
