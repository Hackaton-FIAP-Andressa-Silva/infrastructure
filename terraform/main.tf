terraform {
  required_version = ">= 1.8.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "s3" {
    bucket = "fiap-hackaton-terraform-state"
    key    = "architecture-analyzer/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region
}

module "networking" {
  source      = "./modules/networking"
  environment = var.environment
}

module "s3" {
  source      = "./modules/s3"
  environment = var.environment
}

module "sqs" {
  source      = "./modules/sqs"
  environment = var.environment
}

module "rds" {
  source             = "./modules/rds"
  environment        = var.environment
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
}

module "documentdb" {
  source               = "./modules/documentdb"
  environment          = var.environment
  vpc_id               = module.networking.vpc_id
  private_subnet_ids   = module.networking.private_subnet_ids
  mongodb_url_override = var.mongodb_url
}

module "ecr" {
  source      = "./modules/ecr"
  environment = var.environment
}

module "iam" {
  source            = "./modules/iam"
  environment       = var.environment
  s3_bucket_arn     = module.s3.bucket_arn
  sqs_queue_arn     = module.sqs.queue_arn
  sqs_dlq_arn       = module.sqs.dlq_arn
}

module "ecs" {
  source                     = "./modules/ecs"
  environment                = var.environment
  vpc_id                     = module.networking.vpc_id
  public_subnet_ids          = module.networking.public_subnet_ids
  private_subnet_ids         = module.networking.private_subnet_ids
  upload_service_image       = "${module.ecr.upload_service_repo_url}:latest"
  ai_processing_image        = "${module.ecr.ai_processing_repo_url}:latest"
  report_service_image       = "${module.ecr.report_service_repo_url}:latest"
  api_gateway_image          = "${module.ecr.api_gateway_repo_url}:latest"
  upload_service_task_role   = module.iam.upload_service_role_arn
  ai_processing_task_role    = module.iam.ai_processing_role_arn
  db_endpoint                = module.rds.endpoint
  db_url_secret_arn          = module.rds.db_url_secret_arn
  mongodb_url_secret_arn     = module.documentdb.mongodb_url_secret_arn
  sqs_queue_url              = module.sqs.queue_url
  s3_bucket_name             = module.s3.bucket_name
  aws_region                 = var.aws_region
  openai_api_key_secret_arn  = aws_secretsmanager_secret.google_api_key.arn
  internal_token_secret_arn  = aws_secretsmanager_secret.internal_token.arn
  api_key_secret_arn         = aws_secretsmanager_secret.api_key.arn
}

resource "aws_secretsmanager_secret" "api_key" {
  name        = "${var.environment}/fiap-hackaton/api-key"
  description = "External API key for clients (X-API-Key header)"
}

resource "aws_secretsmanager_secret_version" "api_key" {
  secret_id     = aws_secretsmanager_secret.api_key.id
  secret_string = var.api_key
}

# Secrets
resource "aws_secretsmanager_secret" "google_api_key" {
  name        = "${var.environment}/fiap-hackaton/google-api-key"
  description = "Google Gemini API Key for AI processing service"
}

resource "aws_secretsmanager_secret_version" "google_api_key" {
  secret_id     = aws_secretsmanager_secret.google_api_key.id
  secret_string = var.google_api_key
}

resource "aws_secretsmanager_secret" "internal_token" {
  name        = "${var.environment}/fiap-hackaton/internal-service-token"
  description = "Internal token for service-to-service authentication"
}

resource "aws_secretsmanager_secret_version" "internal_token" {
  secret_id     = aws_secretsmanager_secret.internal_token.id
  secret_string = var.internal_service_token
}

# ci trigger
