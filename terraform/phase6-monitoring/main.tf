terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "cloud-ops-lab-tfstate"
    key    = "phase6-monitoring/terraform.tfstate"
    region = "ap-northeast-1"
  }
}


provider "aws" {
  region = "ap-northeast-1"
}

# ── SNS ──────────────────────────────────────────────
resource "aws_sns_topic" "site_alert" {
  name = "site-monitor-alert"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.site_alert.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ── IAM Role for Lambda ───────────────────────────────
resource "aws_iam_role" "lambda_exec" {
  name = "site-monitor-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "site-monitor-lambda-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.site_alert.arn
      }
    ]
  })
}

# ── Lambda Function ───────────────────────────────────
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/site_monitor.py"
  output_path = "${path.module}/lambda/site_monitor.zip"
}

resource "aws_lambda_function" "site_monitor" {
  function_name    = "site-monitor"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "site_monitor.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 15

  environment {
    variables = {
      TARGET_URL    = var.target_url
      SNS_TOPIC_ARN = aws_sns_topic.site_alert.arn
      TIMEOUT_SECONDS = "10"
    }
  }
}

# ── EventBridge ───────────────────────────────────────
resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "site-monitor-schedule"
  schedule_expression = var.schedule_expression
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.schedule.name
  target_id = "site-monitor-lambda"
  arn       = aws_lambda_function.site_monitor.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.site_monitor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}
# trigger CI
# retrigger
# retrigger2
# retrigger3
