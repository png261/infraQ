terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the CloudWatch alarm will be created."
  type        = string
  default     = "us-east-1"
}

variable "alarm_name" {
  description = "Name of the CloudWatch Metric Alarm."
  type        = string
  default     = "ec2-high-cpu-utilization-alarm"
}

variable "cpu_threshold" {
  description = "CPU utilization percentage threshold that triggers the alarm."
  type        = number
  default     = 80
}

variable "evaluation_periods" {
  description = "Number of periods over which data is compared to the threshold."
  type        = number
  default     = 2
}

variable "period" {
  description = "Period in seconds over which the metric statistic is applied."
  type        = number
  default     = 300
}

resource "aws_cloudwatch_metric_alarm" "ec2_high_cpu" {
  alarm_name          = var.alarm_name
  alarm_description   = "Alarm when average EC2 CPU utilization exceeds ${var.cpu_threshold}%."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.evaluation_periods
  threshold           = var.cpu_threshold
  period              = var.period
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"

  treat_missing_data = "notBreaching"

  actions_enabled = false
}