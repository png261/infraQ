variable "kendra_role_name" {
  description = "Name for the IAM role assumed by Amazon Kendra."
  type        = string
  default     = "example-kendra-role"
}

variable "kendra_index_name" {
  description = "Name for the Amazon Kendra index."
  type        = string
  default     = "example-kendra-index"
}

variable "kendra_data_source_name" {
  description = "Name for the Amazon Kendra data source."
  type        = string
  default     = "example-kendra-webcrawler-source"
}

variable "seed_urls" {
  description = "Seed URLs for the Kendra web crawler data source."
  type        = list(string)
  default     = ["https://example.com"]
}

variable "proxy_host" {
  description = "Proxy host used by the Kendra web crawler data source."
  type        = string
  default     = "proxy.example.com"
}

variable "proxy_port" {
  description = "Proxy port used by the Kendra web crawler data source."
  type        = number
  default     = 8080
}

variable "proxy_credentials_secret_name" {
  description = "Name for the AWS Secrets Manager secret containing proxy credentials for Kendra."
  type        = string
  default     = "example-kendra-proxy-credentials"
}

variable "proxy_username" {
  description = "Proxy username stored in AWS Secrets Manager for the Kendra web crawler."
  type        = string
  sensitive   = true
  default     = "example-user"
}

variable "proxy_password" {
  description = "Proxy password stored in AWS Secrets Manager for the Kendra web crawler. Override for real deployments."
  type        = string
  sensitive   = true
  default     = "example-password"
}
