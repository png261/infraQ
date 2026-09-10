provider "aws" {
  region = "us-east-1"
}

resource "aws_cloudwatch_metric_alarm" "foobar" {
  alarm_name          = "foobar"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 80

  insufficient_data_actions = []
}
