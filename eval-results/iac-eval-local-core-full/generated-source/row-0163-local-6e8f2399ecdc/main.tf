resource "aws_dynamodb_table" "east" {
  name             = "iac-eval-global-table"
  hash_key         = "id"
  billing_mode     = "PAY_PER_REQUEST"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_dynamodb_table" "west_1" {
  provider = aws.us_west_1

  name             = aws_dynamodb_table.east.name
  hash_key         = "id"
  billing_mode     = "PAY_PER_REQUEST"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_dynamodb_table" "west_2" {
  provider = aws.us_west_2

  name             = aws_dynamodb_table.east.name
  hash_key         = "id"
  billing_mode     = "PAY_PER_REQUEST"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_dynamodb_global_table" "this" {
  name = aws_dynamodb_table.east.name

  replica {
    region_name = "us-east-1"
  }

  replica {
    region_name = "us-west-1"
  }

  replica {
    region_name = "us-west-2"
  }

  depends_on = [
    aws_dynamodb_table.east,
    aws_dynamodb_table.west_1,
    aws_dynamodb_table.west_2,
  ]
}
