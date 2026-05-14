variable "environment" { type = string }

locals {
  name = "fiap-hackaton-${var.environment}"
  tags = { Environment = var.environment, Project = "fiap-hackaton" }
}

resource "aws_s3_bucket" "diagrams" {
  bucket = "${local.name}-architecture-diagrams"
  tags   = local.tags
}

resource "aws_s3_bucket_versioning" "diagrams" {
  bucket = aws_s3_bucket.diagrams.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "diagrams" {
  bucket = aws_s3_bucket.diagrams.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "diagrams" {
  bucket                  = aws_s3_bucket.diagrams.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "diagrams" {
  bucket = aws_s3_bucket.diagrams.id
  rule {
    id     = "expire-old-uploads"
    status = "Enabled"
    expiration { days = 90 }
  }
}

output "bucket_name" { value = aws_s3_bucket.diagrams.bucket }
output "bucket_arn"  { value = aws_s3_bucket.diagrams.arn }
