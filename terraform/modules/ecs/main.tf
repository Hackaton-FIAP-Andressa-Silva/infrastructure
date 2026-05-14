variable "environment"                  { type = string }
variable "vpc_id"                        { type = string }
variable "public_subnet_ids"             { type = list(string) }
variable "private_subnet_ids"            { type = list(string) }
variable "upload_service_image"          { type = string }
variable "ai_processing_image"           { type = string }
variable "report_service_image"          { type = string }
variable "api_gateway_image"             { type = string }
variable "upload_service_task_role"      { type = string }
variable "ai_processing_task_role"       { type = string }
variable "db_endpoint"                   { type = string }
variable "sqs_queue_url"                 { type = string }
variable "s3_bucket_name"               { type = string }
variable "aws_region"                    { type = string }
variable "openai_api_key_secret_arn" {
  type      = string
  sensitive = true
}
variable "internal_token_secret_arn" {
  type      = string
  sensitive = true
}
variable "api_key_secret_arn" {
  type      = string
  sensitive = true
}
variable "db_url_secret_arn" {
  type      = string
  sensitive = true
}
variable "mongodb_url_secret_arn" {
  type      = string
  sensitive = true
}

# HTTPS / ACM — optional; if provided, enables TLS on the ALB
variable "domain_name" {
  description = "Public domain name for the ALB (e.g. api.example.com). Required when enable_https = true."
  type        = string
  default     = ""
}

variable "enable_https" {
  description = "When true, provisions an ACM certificate and adds an HTTPS listener on port 443 with HTTP→HTTPS redirect."
  type        = bool
  default     = false
}

locals {
  name = "fiap-hackaton-${var.environment}"
  tags = { Environment = var.environment, Project = "fiap-hackaton" }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.name}"
  retention_in_days = 30
  tags              = local.tags
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${local.name}-cluster"
  tags = local.tags

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# AWS Academy restricts iam:CreateRole.
# Use the pre-existing LabRole which already has ECS execution permissions.
data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

# Security Groups
resource "aws_security_group" "alb" {
  name        = "${local.name}-alb-sg"
  description = "ALB inbound HTTP and HTTPS traffic"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = local.tags
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${local.name}-ecs-tasks-sg"
  description = "ECS tasks - inbound from ALB only"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 80
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Internal VPC traffic"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = local.tags
}

# ALB
resource "aws_lb" "main" {
  name               = "${local.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids
  tags               = local.tags
}

resource "aws_lb_target_group" "api_gateway" {
  name        = "${local.name}-api-gw-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }
  tags = local.tags
}

# ACM certificate (DNS validation) — created only when enable_https = true
resource "aws_acm_certificate" "api" {
  count             = var.enable_https ? 1 : 0
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
  tags = local.tags
}

# HTTP listener — forwards when HTTPS disabled, redirects when enabled
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = var.enable_https ? "redirect" : "forward"

    dynamic "redirect" {
      for_each = var.enable_https ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    dynamic "forward" {
      for_each = var.enable_https ? [] : [1]
      content {
        target_group {
          arn = aws_lb_target_group.api_gateway.arn
        }
      }
    }
  }
}

# HTTPS listener — only when enable_https = true
resource "aws_lb_listener" "https" {
  count             = var.enable_https ? 1 : 0
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.api[0].arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_gateway.arn
  }

  depends_on = [aws_acm_certificate.api]
}

# ─── Internal ALB (service-to-service communication) ───────────────────────
# Cloud Map service discovery is unavailable in AWS Academy.
# An internal ALB gives api-gateway and ai-processing stable DNS hostnames.
resource "aws_security_group" "internal_alb" {
  name        = "${local.name}-int-alb-sg"
  description = "Internal ALB - ECS to ECS traffic"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 8001
    to_port     = 8001
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    from_port   = 8003
    to_port     = 8003
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

resource "aws_lb" "internal" {
  name               = "${local.name}-int-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.internal_alb.id]
  subnets            = var.private_subnet_ids
  tags               = local.tags
}

resource "aws_lb_target_group" "upload_service" {
  name        = "${local.name}-upload-svc-tg"
  port        = 8001
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }
  tags = local.tags
}

resource "aws_lb_target_group" "report_service" {
  name        = "${local.name}-report-svc-tg"
  port        = 8003
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }
  tags = local.tags
}

resource "aws_lb_listener" "upload_internal" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 8001
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.upload_service.arn
  }
}

resource "aws_lb_listener" "report_internal" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 8003
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.report_service.arn
  }
}

# ─── Task Definitions ───────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "upload_service" {
  family                   = "${local.name}-upload-service"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = data.aws_iam_role.lab_role.arn
  task_role_arn            = var.upload_service_task_role

  container_definitions = jsonencode([{
    name      = "upload-service"
    image     = var.upload_service_image
    essential = true
    portMappings = [{ containerPort = 8001, protocol = "tcp" }]
    environment = [
      { name = "AWS_REGION",      value = var.aws_region },
      { name = "S3_BUCKET_NAME",  value = var.s3_bucket_name },
      { name = "SQS_QUEUE_URL",   value = var.sqs_queue_url },
    ]
    secrets = [
      { name = "DATABASE_URL",           valueFrom = var.db_url_secret_arn },
      { name = "INTERNAL_SERVICE_TOKEN", valueFrom = var.internal_token_secret_arn }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "upload-service"
      }
    }
  }])
  tags = local.tags
}

resource "aws_ecs_task_definition" "ai_processing" {
  family                   = "${local.name}-ai-processing"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = data.aws_iam_role.lab_role.arn
  task_role_arn            = var.ai_processing_task_role

  container_definitions = jsonencode([{
    name      = "ai-processing-service"
    image     = var.ai_processing_image
    essential = true
    environment = [
      { name = "AWS_REGION",          value = var.aws_region },
      { name = "S3_BUCKET_NAME",      value = var.s3_bucket_name },
      { name = "SQS_QUEUE_URL",       value = var.sqs_queue_url },
      { name = "UPLOAD_SERVICE_URL",  value = "http://${aws_lb.internal.dns_name}:8001" },
      { name = "REPORT_SERVICE_URL",  value = "http://${aws_lb.internal.dns_name}:8003" },
    ]
    secrets = [
      { name = "GOOGLE_API_KEY",         valueFrom = var.openai_api_key_secret_arn },
      { name = "INTERNAL_SERVICE_TOKEN", valueFrom = var.internal_token_secret_arn },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ai-processing"
      }
    }
  }])
  tags = local.tags
}

resource "aws_ecs_task_definition" "report_service" {
  family                   = "${local.name}-report-service"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = data.aws_iam_role.lab_role.arn

  container_definitions = jsonencode([{
    name      = "report-service"
    image     = var.report_service_image
    essential = true
    portMappings = [{ containerPort = 8003, protocol = "tcp" }]
    environment = [
      { name = "MONGODB_DATABASE", value = "report_db" },
    ]
    secrets = [
      { name = "MONGODB_URL",            valueFrom = var.mongodb_url_secret_arn },
      { name = "INTERNAL_SERVICE_TOKEN", valueFrom = var.internal_token_secret_arn }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "report-service"
      }
    }
  }])
  tags = local.tags
}

resource "aws_ecs_task_definition" "api_gateway" {
  family                   = "${local.name}-api-gateway"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = data.aws_iam_role.lab_role.arn

  container_definitions = jsonencode([{
    name      = "api-gateway"
    image     = var.api_gateway_image
    essential = true
    portMappings = [{ containerPort = 80, protocol = "tcp" }]
    environment = [
      { name = "UPLOAD_SERVICE_URL", value = "http://${aws_lb.internal.dns_name}:8001" },
      { name = "REPORT_SERVICE_URL", value = "http://${aws_lb.internal.dns_name}:8003" },
    ]
    secrets = [
      { name = "API_KEY", valueFrom = var.api_key_secret_arn }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "api-gateway"
      }
    }
  }])
  tags = local.tags
}

# ─── ECS Services ───────────────────────────────────────────────────────────

resource "aws_ecs_service" "upload_service" {
  name            = "${local.name}-upload-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.upload_service.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.upload_service.arn
    container_name   = "upload-service"
    container_port   = 8001
  }

  tags = local.tags
}

resource "aws_ecs_service" "ai_processing" {
  name            = "${local.name}-ai-processing"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.ai_processing.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  tags = local.tags
}

resource "aws_ecs_service" "report_service" {
  name            = "${local.name}-report-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.report_service.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.report_service.arn
    container_name   = "report-service"
    container_port   = 8003
  }

  tags = local.tags
}

resource "aws_ecs_service" "api_gateway" {
  name            = "${local.name}-api-gateway"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api_gateway.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api_gateway.arn
    container_name   = "api-gateway"
    container_port   = 80
  }

  tags = local.tags
}

output "alb_dns_name"         { value = aws_lb.main.dns_name }
output "acm_certificate_arn"  { value = var.enable_https ? aws_acm_certificate.api[0].arn : "" }
output "alb_dns_validation_records" {
  description = "DNS validation records to add to your domain registrar when enable_https = true."
  value       = var.enable_https ? aws_acm_certificate.api[0].domain_validation_options : toset([])
}
