variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod"
  }
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "google_api_key" {
  description = "Google Gemini API Key for the AI processing service"
  type        = string
  sensitive   = true
}

variable "internal_service_token" {
  description = "Secret token for internal service-to-service authentication"
  type        = string
  sensitive   = true
  default     = "change-me-in-production"
}
