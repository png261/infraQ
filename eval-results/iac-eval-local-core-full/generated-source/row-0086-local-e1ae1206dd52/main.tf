resource "aws_route53_traffic_policy" "this" {
  name     = "example-traffic-policy"
  document = jsonencode({
    AWSPolicyFormatVersion = "2015-10-01"
    RecordType             = "A"
    StartRule              = "primary"
    Endpoints = {
      primary = {
        Type  = "value"
        Value = "192.0.2.1"
      }
    }
    Rules = {
      primary = {
        RuleType = "simple"
        EndpointReference = "primary"
      }
    }
  })
}
