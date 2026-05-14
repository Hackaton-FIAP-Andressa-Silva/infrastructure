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

variable "api_key" {
  description = "External API key for clients (sent in X-API-Key header)"
  type        = string
  sensitive   = true
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

variable "mongodb_url" {
  description = "MongoDB connection URL. Use MongoDB Atlas free tier (DocumentDB instances blocked in AWS Academy)."
  type        = string
  sensitive   = true
  default     = ""
}
