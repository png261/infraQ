resource "aws_dynamodb_table" "benchmark" {
  name           = "iac-eval-dynamodb-table"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_dynamodb_table_item" "benchmark" {
  table_name = aws_dynamodb_table.benchmark.name
  hash_key   = aws_dynamodb_table.benchmark.hash_key

  item = jsonencode({
    id = {
      S = "item-001"
    }
    message = {
      S = "Hello from Terraform"
    }
  })
}
