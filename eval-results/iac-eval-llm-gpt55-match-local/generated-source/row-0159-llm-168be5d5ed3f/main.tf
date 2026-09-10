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
  description = "AWS region where resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "alarm_namespace" {
  description = "CloudWatch metric namespace used for the example metric alarms."
  type        = string
  default     = "AWS/EC2"
}

variable "instance_id" {
  description = "Example EC2 instance ID used as a CloudWatch metric dimension."
  type        = string
  default     = "i-0123456789abcdef0"
}

resource "aws_sns_topic" "cloudwatch_alarm_topic" {
  name = "cloudwatch-composite-alarm-topic"
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "example-high-cpu-alarm"
  alarm_description   = "Triggers when EC2 CPU utilization is greater than or equal to 80 percent."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  period              = 300
  metric_name         = "CPUUtilization"
  namespace           = var.alarm_namespace
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = var.instance_id
  }
}

resource "aws_cloudwatch_metric_alarm" "high_status_check_failures" {
  alarm_name          = "example-status-check-failed-alarm"
  alarm_description   = "Triggers when EC2 status checks fail."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  period              = 300
  metric_name         = "StatusCheckFailed"
  namespace           = var.alarm_namespace
  statistic           = "Maximum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = var.instance_id
  }
}

resource "aws_cloudwatch_composite_alarm" "example" {
  alarm_name        = "example-composite-cloudwatch-alarm"
  alarm_description = "Composite alarm that triggers when either high CPU or EC2 status check failures occur."

  alarm_rule = "ALARM(\"${aws_cloudwatch_metric_alarm.high_cpu.alarm_name}\") OR ALARM(\"${aws_cloudwatch_metric_alarm.high_status_check_failures.alarm_name}\")"

  alarm_actions = [
    aws_sns_topic.cloudwatch_alarm_topic.arn
  ]

  ok_actions = [
    aws_sns_topic.cloudwatch_alarm_topic.arn
  ]

  actions_enabled = true
}