variable "region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix used for benchmark resource names."
  type        = string
  default     = "aptos"
}

variable "ecr_repository_name" {
  description = "Existing ECR repository name used to fetch the stable image metadata."
  type        = string
  default     = "aptos"
}

variable "cluster_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.29"
}

variable "node_instance_types" {
  description = "EC2 instance types for the EKS managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_count" {
  description = "Desired, minimum, and maximum node count for the benchmark node group."
  type        = number
  default     = 2
}
