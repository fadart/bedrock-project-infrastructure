terraform {
  backend "s3" {
    bucket = "bedrock-terraform-state-035786426828"
    key    = "project-bedrock/terraform.tfstate"
    region = "us-east-1"
  }
}
