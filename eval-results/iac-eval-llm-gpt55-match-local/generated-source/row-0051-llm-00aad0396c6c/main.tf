terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the Lex V2 bot will be created."
  type        = string
  default     = "us-east-1"
}

variable "bot_name" {
  description = "Name of the Amazon Lex V2 bot."
  type        = string
  default     = "example-lexv2-bot"
}

data "aws_iam_policy_document" "lex_assume_role_policy" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lexv2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lex_bot_role" {
  name               = "example-lexv2-bot-role"
  assume_role_policy = data.aws_iam_policy_document.lex_assume_role_policy.json
}

data "aws_iam_policy_document" "lex_bot_permissions" {
  statement {
    effect = "Allow"

    actions = [
      "polly:SynthesizeSpeech",
      "comprehend:DetectSentiment"
    ]

    resources = ["*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "lex_bot_policy" {
  name        = "example-lexv2-bot-policy"
  description = "Permissions for the Amazon Lex V2 bot service role."
  policy      = data.aws_iam_policy_document.lex_bot_permissions.json
}

resource "aws_iam_role_policy_attachment" "lex_bot_policy_attachment" {
  role       = aws_iam_role.lex_bot_role.name
  policy_arn = aws_iam_policy.lex_bot_policy.arn
}

resource "aws_lexv2models_bot" "example" {
  name                        = var.bot_name
  description                 = "Example Amazon Lex V2 bot created with Terraform."
  role_arn                    = aws_iam_role.lex_bot_role.arn
  idle_session_ttl_in_seconds = 300

  data_privacy {
    child_directed = false
  }

  depends_on = [
    aws_iam_role_policy_attachment.lex_bot_policy_attachment
  ]
}

output "lexv2_bot_id" {
  description = "The ID of the Amazon Lex V2 bot."
  value       = aws_lexv2models_bot.example.id
}

output "lexv2_bot_arn" {
  description = "The ARN of the Amazon Lex V2 bot."
  value       = aws_lexv2models_bot.example.arn
}

output "lexv2_bot_name" {
  description = "The name of the Amazon Lex V2 bot."
  value       = aws_lexv2models_bot.example.name
}