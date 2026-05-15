# Infrastructure

Infrastructure-as-code and local development stack for the FIAP Architecture Analyzer — a microservices system that accepts architecture diagrams, analyzes them with Google Gemini Vision, and returns structured reports.

## Architecture Overview

```
                        ┌──────────────────────────────────────────────────┐
                        │                   AWS / Local                    │
                        │                                                  │
  Client ──────────────►│  API Gateway (Nginx)  :8080                      │
   X-API-Key            │       │          │                               │
                        │       ▼          ▼                               │
                        │  Upload Service  Report Service                  │
                        │    :8001           :8003                         │
                        │       │              ▲                           │
                        │    S3 + SQS          │                           │
                        │       │              │                           │
                        │       ▼              │                           │
                        │  AI Processing Service                           │
                        │  (SQS consumer — Gemini Vision)                  │
                        └──────────────────────────────────────────────────┘
```

### Services

| Service | Port | Datastore | Description |
|---|---|---|---|
| `api-gateway` | 8080 | — | Nginx reverse proxy; validates `X-API-Key`, rate-limits |
| `upload-service` | 8001 | PostgreSQL + S3 + SQS | Accepts diagram uploads, tracks status |
| `ai-processing-service` | — | SQS + S3 | SQS worker; calls Gemini Vision; posts report |
| `report-service` | 8003 | MongoDB | Stores and serves AI-generated reports |

### AWS Components (Production)

| Component | Purpose |
|---|---|
| **ECS Fargate** | Container runtime for all 4 services |
| **ALB (public)** | External entry point; routes to api-gateway |
| **ALB (internal)** | Internal routing between api-gateway and upstream services |
| **ECR** | Private container registry (one repo per service) |
| **RDS PostgreSQL 16** | upload-service database |
| **MongoDB Atlas M0** | report-service — free-tier managed MongoDB (replaces DocumentDB; blocked in AWS Academy) |
| **S3** | Diagram storage |
| **SQS + DLQ** | Async job queue between upload and AI services |
| **Secrets Manager** | `GOOGLE_API_KEY`, `INTERNAL_SERVICE_TOKEN`, `API_KEY`, `MONGODB_URL` |
| **VPC** | Isolated network; services run in private subnets; ALBs in public/private |
| **IAM** | `LabRole` (AWS Academy pre-provisioned role) used as ECS task execution role |

### Local Stack (Docker Compose)

| Component | Replaces |
|---|---|
| `postgres:16-alpine` | RDS |
| `mongo:7.0` | MongoDB Atlas |
| `localstack:3.4` (S3 + SQS) | AWS S3 + SQS |

---

## Local Development

### Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) ≥ 4.x
- A Google Gemini API key — get one free at [aistudio.google.com](https://aistudio.google.com) (use a project **without billing** for the free tier)

### 1. All services live in the same repository

```
hackaton-fiap/        ← monorepo root
├── infrastructure/     ← you are here
├── upload-service/
├── ai-processing-service/
├── report-service/
└── api-gateway/
```

### 2. Configure environment

```bash
cd infrastructure
cp .env.local .env
```

Open `.env` and set your real values:

```env
# Secret key clients must send in X-API-Key header
API_KEY=your-strong-random-key

# Google Gemini API key (required for AI analysis)
GOOGLE_API_KEY=AIza...your-key...
```

### 3. Start the full stack

```bash
docker compose up --build
```

This will:
1. Start PostgreSQL, MongoDB, and LocalStack (S3 + SQS)
2. Run Alembic migrations (`migrate` one-shot container)
3. Start all four services
4. Initialize S3 bucket and SQS queue via `scripts/init-localstack.sh`

### 4. Verify everything is running

```bash
curl http://localhost:8080/health
# → {"status": "ok"}
```

### 5. Upload a diagram

```bash
curl -X POST http://localhost:8080/api/v1/uploads \
  -H "X-API-Key: your-strong-random-key" \
  -F "file=@/path/to/diagram.png"
```

```json
{"upload_id": "...", "status": "RECEIVED", ...}
```

### 6. Poll status

```bash
curl http://localhost:8080/api/v1/uploads/{upload_id}/status \
  -H "X-API-Key: your-strong-random-key"
```

Status transitions: `RECEIVED` → `PROCESSING` → `ANALYZED` (or `FAILED`)

### 7. Get the report

```bash
curl http://localhost:8080/api/v1/reports/{upload_id} \
  -H "X-API-Key: your-strong-random-key"
```

### Useful commands

```bash
# Rebuild and restart a single service (picks up code changes)
docker compose up --build --no-deps -d ai-processing-service

# View logs for a specific service
docker compose logs -f ai-processing-service

# Stop everything and remove volumes
docker compose down -v
```

---

## AWS Deployment (Terraform)

### Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.8
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) configured with credentials that have admin permissions
- Docker (to build and push images to ECR)

### 1. Create the Terraform state bucket

This only needs to be done once. The bucket name must match `main.tf`.

```bash
aws s3 mb s3://fiap-hackaton-terraform-state --region us-east-1
aws s3api put-bucket-versioning \
  --bucket fiap-hackaton-terraform-state \
  --versioning-configuration Status=Enabled
```

### 2. Initialize Terraform

```bash
cd terraform
terraform init
```

### 3. Plan

```bash
terraform plan \
  -var="environment=prod" \
  -var="google_api_key=AIza...your-key..." \
  -var="internal_service_token=your-strong-random-token"
```

Review the plan. Expected resources: VPC, subnets, RDS, DocumentDB, S3, SQS, ECR repos, ECS cluster + services, ALB, IAM roles, Secrets Manager secrets.

### 4. Apply

```bash
terraform apply \
  -var="environment=prod" \
  -var="google_api_key=AIza...your-key..." \
  -var="internal_service_token=your-strong-random-token"
```

> **Never** pass secrets via `-var` in CI. Use environment variables instead:
> ```bash
> export TF_VAR_google_api_key="AIza..."
> export TF_VAR_internal_service_token="..."
> terraform apply -var="environment=prod"
> ```

### 5. Retrieve outputs

```bash
terraform output
```

```
alb_dns_name       = "fiap-hackaton-prod-alb-xxxx.us-east-1.elb.amazonaws.com"
s3_bucket_name     = "fiap-hackaton-prod-diagrams"
sqs_queue_url      = "https://sqs.us-east-1.amazonaws.com/123456789/..."
ecr_repositories   = { upload_service = "...", ai_processing = "...", ... }
```

### 6. Build and push Docker images to ECR

Run this from the parent folder that contains all service repos:

```bash
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=us-east-1
REGISTRY=$AWS_ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com

aws ecr get-login-password --region $AWS_REGION \
  | docker login --username AWS --password-stdin $REGISTRY

for SERVICE in upload-service ai-processing-service report-service api-gateway; do
  docker build -t $REGISTRY/fiap-hackaton-prod/$SERVICE:latest $SERVICE/
  docker push $REGISTRY/fiap-hackaton-prod/$SERVICE:latest
done
```

### 7. Force ECS re-deployment

```bash
for SERVICE in upload-service ai-processing-service report-service api-gateway; do
  aws ecs update-service \
    --cluster fiap-hackaton-prod-cluster \
    --service fiap-hackaton-prod-$SERVICE \
    --force-new-deployment \
    --region us-east-1
done
```

### 8. Test the production endpoint

```bash
ALB=$(terraform output -raw alb_dns_name)

curl http://$ALB/health
curl -X POST http://$ALB/api/v1/uploads \
  -H "X-API-Key: your-api-key" \
  -F "file=@/path/to/diagram.png"
```

### Tear down

```bash
terraform destroy \
  -var="environment=prod" \
  -var="google_api_key=placeholder" \
  -var="internal_service_token=placeholder"
```

---

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `API_KEY` | ✅ | Secret key clients must send in `X-API-Key` |
| `GOOGLE_API_KEY` | ✅ | Google Gemini API key |

All other variables (database URLs, AWS endpoints, internal tokens) are injected automatically by Docker Compose (local) or ECS task definitions (AWS).

---

## CI/CD (GitHub Actions)

The workflow in `.github/workflows/terraform.yml` runs `terraform plan` on every pull request and `terraform apply` on merge to `main`.

### Required GitHub Secrets

Configure these in **Settings → Secrets and variables → Actions** of this repository:

| Secret | Description |
|---|---|
| `AWS_ACCESS_KEY_ID` | IAM user or role with permissions to manage all resources |
| `AWS_SECRET_ACCESS_KEY` | Corresponding secret |
| `GOOGLE_API_KEY` | Google Gemini API key |
| `INTERNAL_SERVICE_TOKEN` | Random secret for service-to-service auth |

---

## Repository Structure

```
infrastructure/
├── docker-compose.yml        # Local full-stack
├── .env.local                # Template — copy to .env and fill in secrets
├── scripts/
│   └── init-localstack.sh    # Creates S3 bucket + SQS queue in LocalStack
└── terraform/
    ├── main.tf               # Root module — wires all modules together
    ├── variables.tf
    ├── outputs.tf
    └── modules/
        ├── networking/       # VPC, subnets, NAT, security groups
        ├── s3/               # Diagram storage bucket
        ├── sqs/              # Analysis queue + DLQ
        ├── rds/              # PostgreSQL for upload-service
        ├── documentdb/       # MongoDB-compatible for report-service
        ├── ecr/              # Container registries
        ├── iam/              # Task roles with least-privilege policies
        └── ecs/              # Cluster, task definitions, services, ALB
```
