variable "environment"        { type = string }
variable "vpc_id"             { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "mongodb_url_override" {
  description = "External MongoDB URL (e.g., MongoDB Atlas). Bypasses the DocumentDB cluster URL."
  type        = string
  default     = ""
  sensitive   = true
}

locals {
  name = "fiap-hackaton-${var.environment}"
  tags = { Environment = var.environment, Project = "fiap-hackaton" }
}

resource "aws_security_group" "docdb" {
  name        = "${local.name}-docdb-sg"
  description = "DocumentDB access from ECS tasks"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = local.tags
}

resource "aws_docdb_subnet_group" "main" {
  name       = "${local.name}-docdb-subnet"
  subnet_ids = var.private_subnet_ids
  tags       = local.tags
}

resource "random_password" "docdb" {
  length  = 32
  special = false
}

resource "aws_docdb_cluster_parameter_group" "main" {
  family      = "docdb4.0"
  name        = "${local.name}-docdb-params"
  description = "TLS disabled - internal VPC access only"

  parameter {
    name  = "tls"
    value = "disabled"
  }
  tags = local.tags
}

resource "aws_docdb_cluster" "main" {
  cluster_identifier               = "${local.name}-docdb"
  engine                           = "docdb"
  engine_version                   = "4.0.0"
  master_username                  = "docdbadmin"
  master_password                  = random_password.docdb.result
  db_subnet_group_name             = aws_docdb_subnet_group.main.name
  db_cluster_parameter_group_name  = aws_docdb_cluster_parameter_group.main.name
  vpc_security_group_ids           = [aws_security_group.docdb.id]
  skip_final_snapshot              = var.environment != "prod"
  deletion_protection              = var.environment == "prod"
  storage_encrypted                = true
  tags                             = local.tags
}

resource "aws_docdb_cluster_instance" "main" {
  # count = 0: AWS Academy blocks rds:CreateDBInstance.
  # Use MongoDB Atlas free tier and pass the URL via mongodb_url_override.
  count              = 0
  identifier         = "${local.name}-docdb-${count.index}"
  cluster_identifier = aws_docdb_cluster.main.id
  instance_class     = "db.t3.medium"
  tags               = local.tags
}

resource "aws_secretsmanager_secret" "docdb_credentials" {
  name = "${var.environment}/fiap-hackaton/docdb-credentials"
  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "docdb_credentials" {
  secret_id = aws_secretsmanager_secret.docdb_credentials.id
  secret_string = jsonencode({
    username = aws_docdb_cluster.main.master_username
    password = random_password.docdb.result
    host     = aws_docdb_cluster.main.endpoint
    port     = 27017
  })
}

output "endpoint" { value = aws_docdb_cluster.main.endpoint }

# Full MongoDB URL with credentials stored as a secret for ECS task injection
resource "aws_secretsmanager_secret" "mongodb_url" {
  name = "${var.environment}/fiap-hackaton/report-service-mongodb-url"
  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "mongodb_url" {
  secret_id     = aws_secretsmanager_secret.mongodb_url.id
  secret_string = var.mongodb_url_override != "" ? var.mongodb_url_override : "mongodb://${aws_docdb_cluster.main.master_username}:${random_password.docdb.result}@${aws_docdb_cluster.main.endpoint}:27017/?directConnection=true&authSource=admin"
}

output "mongodb_url_secret_arn" { value = aws_secretsmanager_secret.mongodb_url.arn }
