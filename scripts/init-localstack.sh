#!/bin/bash
set -e

echo "Initializing LocalStack resources..."

# Create S3 bucket
awslocal s3 mb s3://architecture-diagrams
awslocal s3api put-bucket-versioning \
  --bucket architecture-diagrams \
  --versioning-configuration Status=Enabled

echo "S3 bucket 'architecture-diagrams' created."

# Create Dead Letter Queue
awslocal sqs create-queue \
  --queue-name diagram-analysis-dlq \
  --attributes '{"MessageRetentionPeriod":"86400"}'

DLQ_ARN=$(awslocal sqs get-queue-attributes \
  --queue-url http://sqs.us-east-1.localhost.localstack.cloud:4566/000000000000/diagram-analysis-dlq \
  --attribute-names QueueArn \
  --query 'Attributes.QueueArn' \
  --output text)

echo "DLQ ARN: $DLQ_ARN"

# Create main queue with DLQ redrive policy
awslocal sqs create-queue \
  --queue-name diagram-analysis-queue \
  --attributes "{
    \"VisibilityTimeout\": \"300\",
    \"MessageRetentionPeriod\": \"345600\",
    \"RedrivePolicy\": \"{\\\"deadLetterTargetArn\\\":\\\"$DLQ_ARN\\\",\\\"maxReceiveCount\\\":\\\"3\\\"}\"
  }"

echo "SQS queue 'diagram-analysis-queue' created with DLQ redrive policy (max 3 retries)."
echo "LocalStack initialization complete."
