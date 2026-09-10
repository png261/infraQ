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
  alarm_description   = "CloudWatch alarm for EC2 CPU utilization used by Route 53 health check."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 80

  treat_missing_data = "missing"
}

resource "aws_route53_health_check" "foobar_alarm_health_check" {
  type = "CLOUDWATCH_METRIC"

  cloudwatch_alarm_name   = aws_cloudwatch_metric_alarm.foobar.alarm_name
  cloudwatch_alarm_region = "us-east-1"

  insufficient_data_health_status = "Healthy"

  tags = {
    Name = "foobar-cloudwatch-alarm-health-check"
  }
}