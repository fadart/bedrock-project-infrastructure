variable "bucket_name" {
  description = "S3 assets bucket name"
  type        = string
}

variable "lambda_zip_path" {
  description = "Path to the Lambda function zip file"
  type        = string
}
