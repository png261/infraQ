resource "aws_dax_parameter_group" "this" {
  name        = "benchmark-dax-parameter-group"
  description = "Minimal DAX parameter group for IaC benchmark"
}
