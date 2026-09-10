data "archive_file" "cron" {
  type        = "zip"
  source_file = "${path.module}/supplement/cron.py"
  output_path = "${path.module}/cron.zip"
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cron" {
  name               = "cron-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.cron.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "cron" {
  function_name    = "cron-lambda-function"
  filename         = "cron.zip"
  source_code_hash = data.archive_file.cron.output_base64sha256
  role             = aws_iam_role.cron.arn
  handler          = "cron.lambda_handler"
  runtime          = "python3.12"

  depends_on = [aws_iam_role_policy_attachment.lambda_basic_execution]
}

resource "aws_cloudwatch_event_rule" "cron" {
  name                = "cron"
  schedule_expression = "cron(0 7 * * ? *)"
}

resource "aws_cloudwatch_event_target" "cron" {
  rule = aws_cloudwatch_event_rule.cron.name
  arn  = aws_lambda_function.cron.arn
}

resource "aws_lambda_permission" "cron" {
  statement_id  = "AllowExecutionFromEventBridgeCron"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cron.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cron.arn
}
