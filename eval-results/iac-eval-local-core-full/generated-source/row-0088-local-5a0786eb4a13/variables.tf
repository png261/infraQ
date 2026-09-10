variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = "benchmark-eks-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster."
  type        = string
  default     = "1.29"
}
