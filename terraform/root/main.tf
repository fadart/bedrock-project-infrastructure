module "vpc" {
  source = "../modules/vpc"

  vpc_name     = var.vpc_name
  cluster_name = var.cluster_name
}

module "eks" {
  source = "../modules/eks"

  cluster_name       = var.cluster_name
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
}

module "rds_mysql" {
  source = "../modules/rds"

  identifier                 = "bedrock-mysql"
  engine                     = "mysql"
  engine_version             = "8.0"
  db_name                    = "retailstore"
  username                   = "admin"
  password                   = var.mysql_password
  port                       = 3306
  vpc_id                     = module.vpc.vpc_id
  private_subnet_ids         = module.vpc.private_subnet_ids
  eks_node_security_group_id = module.eks.node_security_group_id
}

module "rds_postgres" {
  source = "../modules/rds"

  identifier                 = "bedrock-postgres"
  engine                     = "postgres"
  engine_version             = "15"
  db_name                    = "retailstore"
  username                   = "dbadmin"
  password                   = var.postgres_password
  port                       = 5432
  vpc_id                     = module.vpc.vpc_id
  private_subnet_ids         = module.vpc.private_subnet_ids
  eks_node_security_group_id = module.eks.node_security_group_id
}

module "dynamodb" {
  source = "../modules/dynamodb"

  table_name = "bedrock-retail-store"
}

module "s3_lambda" {
  source = "../modules/s3-lambda"

  bucket_name = "bedrock-assets-${var.student_id}"
}

module "iam" {
  source = "../modules/iam"

  student_id = var.student_id
}
