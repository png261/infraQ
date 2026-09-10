variable "parameter_group_name" {
  description = "Name of the custom DAX parameter group."
  type        = string
  default     = "custom-dax-parameter-group"

  validation {
    condition     = length(trimspace(var.parameter_group_name)) > 0
    error_message = "The DAX parameter group name must not be empty."
  }
}

variable "description" {
  description = "Description for the custom DAX parameter group."
  type        = string
  default     = "Custom DAX parameter group managed by Terraform/OpenTofu."
}

variable "parameters" {
  description = "List of DAX parameter key/value pairs to configure on the parameter group."
  type = list(object({
    key   = string
    value = string
  }))
  default = [
    {
      key   = "query-ttl-millis"
      value = "300000"
    }
  ]

  validation {
    condition = alltrue([
      for parameter in var.parameters : length(trimspace(parameter.key)) > 0
    ])
    error_message = "Each DAX parameter key must not be empty."
  }

  validation {
    condition     = length(var.parameters) == length(toset([for parameter in var.parameters : parameter.key]))
    error_message = "DAX parameter keys must be unique."
  }
}
