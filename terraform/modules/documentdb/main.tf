variable "environment"        { type = string }
variable "vpc_id"             { type = string }
variable "private_subnet_ids" { type = list(string) }

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

resource "aws_docdb_cluster" "main" {
  cluster_identifier      = "${local.name}-docdb"
  engine                  = "docdb"
  master_username         = "docdbadmin"
  master_password         = random_password.docdb.result
  db_subnet_group_name    = aws_docdb_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.docdb.id]
  skip_final_snapshot     = var.environment != "prod"
  deletion_protection     = var.environment == "prod"
  storage_encrypted       = true
  tags                    = local.tags
}

resource "aws_docdb_cluster_instance" "main" {
  count              = var.environment == "prod" ? 2 : 1
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
