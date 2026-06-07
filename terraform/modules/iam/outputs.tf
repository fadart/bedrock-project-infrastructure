output "dev_view_access_key_id" {
  description = "Access key ID for bedrock-dev-view"
  value       = aws_iam_access_key.dev_view.id
}

output "dev_view_secret_access_key" {
  description = "Secret access key for bedrock-dev-view"
  value       = aws_iam_access_key.dev_view.secret
  sensitive   = true
}

output "dev_view_password" {
  description = "Console password for bedrock-dev-view"
  value       = aws_iam_user_login_profile.dev_view.password
  sensitive   = true
}
