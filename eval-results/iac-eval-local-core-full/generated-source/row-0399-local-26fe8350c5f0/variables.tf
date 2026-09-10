variable "oidc_authorization_endpoint" {
  description = "OIDC authorization endpoint URL used by the ALB listener authentication action."
  type        = string
}

variable "oidc_client_id" {
  description = "OIDC client ID used by the ALB listener authentication action."
  type        = string
}

variable "oidc_client_secret" {
  description = "OIDC client secret used by the ALB listener authentication action. This value is sensitive and will still be stored in Terraform/OpenTofu state."
  type        = string
  sensitive   = true
}

variable "oidc_issuer" {
  description = "OIDC issuer URL used by the ALB listener authentication action."
  type        = string
}

variable "oidc_token_endpoint" {
  description = "OIDC token endpoint URL used by the ALB listener authentication action."
  type        = string
}

variable "oidc_user_info_endpoint" {
  description = "OIDC user info endpoint URL used by the ALB listener authentication action."
  type        = string
}
