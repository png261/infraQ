data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "lambda-js-example-exec-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda.js"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "lambda_js" {
  function_name    = "lambda-js-example"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "lambda.handler"
  runtime          = "nodejs20.x"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
}
