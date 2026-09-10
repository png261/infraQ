terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_cloudwatch_metric_alarm" "foobar" {
  alarm_name          = "foobar"
  alarm_description   = "Alarm when average EC2 CPU utilization is greater than or equal to 80% for two consecutive 2-minute periods."

  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"

  period              = 120
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanOrEqualToThreshold"

  treat_missing_data  = "missing"

  insufficient_data_actions = []

  actions_enabled = true
}