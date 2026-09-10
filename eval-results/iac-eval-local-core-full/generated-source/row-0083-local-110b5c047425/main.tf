provider "aws" {
  region = "us-east-1"
}

resource "aws_cloudwatch_metric_alarm" "foobar" {
  alarm_name          = "foobar"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 80
}

resource "aws_route53_health_check" "foobar" {
  type                            = "CLOUDWATCH"
  cloudwatch_alarm_name           = aws_cloudwatch_metric_alarm.foobar.alarm_name
  cloudwatch_alarm_region         = "us-east-1"
  insufficient_data_health_status = "Healthy"
}
