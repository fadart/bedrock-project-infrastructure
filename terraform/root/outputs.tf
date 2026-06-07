output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "region" {
  description = "AWS region"
  value       = var.region
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "assets_bucket_name" {
  description = "S3 assets bucket name"
  value       = module.s3_lambda.bucket_name
}

output "dev_view_access_key_id" {
  description = "Access key ID for bedrock-dev-view"
  value       = module.iam.dev_view_access_key_id
}

output "dev_view_secret_access_key" {
  description = "Secret access key for bedrock-dev-view"
  value       = module.iam.dev_view_secret_access_key
  sensitive   = true
}

output "dev_view_password" {
  description = "Console password for bedrock-dev-view"
  value       = module.iam.dev_view_password
  sensitive   = true
}

output "mysql_endpoint" {
  description = "MySQL RDS endpoint"
  value       = module.rds_mysql.endpoint
}

output "postgres_endpoint" {
  description = "PostgreSQL RDS endpoint"
  value       = module.rds_postgres.endpoint
}
