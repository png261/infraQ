resource "aws_dynamodb_table" "benchmark" {
  name           = "iac-eval-benchmark-table"
  billing_mode   = "PROVISIONED"
  hash_key       = "id"
  read_capacity  = 20
  write_capacity = 20

  attribute {
    name = "id"
    type = "S"
  }
}
