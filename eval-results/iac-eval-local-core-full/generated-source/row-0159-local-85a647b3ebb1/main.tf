resource "aws_cloudwatch_metric_alarm" "ec2_api_usage" {
  alarm_name          = "iac-eval-ec2-api-usage"
  alarm_description   = "Benchmark metric alarm used by the composite alarm."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CallCount"
  namespace           = "AWS/Usage"
  period              = 300
  statistic           = "Sum"
  threshold           = 100

  dimensions = {
    Service  = "EC2"
    Type     = "API"
    Resource = "RunInstances"
    Class    = "None"
  }
}

resource "aws_cloudwatch_composite_alarm" "ec2_api_health" {
  alarm_name        = "iac-eval-composite-ec2-api-health"
  alarm_description = "Composite alarm that enters ALARM when the EC2 API usage metric alarm is in ALARM."
  alarm_rule        = "ALARM(${aws_cloudwatch_metric_alarm.ec2_api_usage.alarm_name})"
}
