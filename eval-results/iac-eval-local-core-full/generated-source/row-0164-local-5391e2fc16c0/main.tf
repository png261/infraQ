resource "aws_dynamodb_table" "benchmark" {
  name         = "iac-eval-dynamodb-kinesis-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_kinesis_stream" "benchmark" {
  name             = "iac-eval-dynamodb-kinesis-stream"
  shard_count      = 1
  retention_period = 24
}

resource "aws_dynamodb_kinesis_streaming_destination" "benchmark" {
  table_name = aws_dynamodb_table.benchmark.name
  stream_arn = aws_kinesis_stream.benchmark.arn
}
