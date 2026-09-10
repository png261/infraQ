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

resource "aws_iam_role" "example_lambda" {
  name               = "example-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "example_lambda_basic" {
  role       = aws_iam_role.example_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "archive_file" "example_lambda" {
  type        = "zip"
  source_file = "${path.module}/index.py"
  output_path = "${path.module}/example_lambda.zip"
}

resource "aws_lambda_function" "example_lambda" {
  function_name    = "example_lambda"
  role             = aws_iam_role.example_lambda.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.example_lambda.output_path
  source_code_hash = data.archive_file.example_lambda.output_base64sha256

  depends_on = [aws_iam_role_policy_attachment.example_lambda_basic]
}

resource "aws_lambda_function_url" "example_lambda" {
  function_name      = aws_lambda_function.example_lambda.function_name
  authorization_type = "AWS_IAM"
}

output "example_lambda_function_url" {
  description = "HTTPS endpoint for the example Lambda function URL. Requests must be signed with AWS IAM credentials."
  value       = aws_lambda_function_url.example_lambda.function_url
}
