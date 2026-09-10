resource "aws_dynamodb_table" "benchmark" {
  name         = "iac-eval-contributor-insights"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "sk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Benchmark = "iac-eval"
  }
}

resource "aws_dynamodb_contributor_insights" "benchmark" {
  table_name = aws_dynamodb_table.benchmark.name
  enabled    = true
}
