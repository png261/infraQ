resource "aws_dynamodb_table" "global" {
  name         = "iac-eval-global-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
}

resource "aws_dynamodb_table_replica" "replica" {
  provider = aws.replica

  global_table_arn = aws_dynamodb_table.global.arn
}
