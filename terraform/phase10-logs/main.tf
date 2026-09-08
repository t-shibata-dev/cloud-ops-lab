terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "cloud-ops-lab-tfstate"
    key    = "phase10-logs/terraform.tfstate"
    region = "ap-northeast-1"
  }
}

provider "aws" {
  region = var.region
}

# ── IAM: CloudWatch Agent ポリシーアタッチ ────────────
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = "cloud-ops-lab-ec2-ssm-role"
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# ── CloudWatch Log Groups ─────────────────────────────
resource "aws_cloudwatch_log_group" "apache_access" {
  name              = "/cloud-ops-lab/ec2/apache/access"
  retention_in_days = 30

  tags = {
    Project = var.project_name
    Phase   = "10"
  }
}

resource "aws_cloudwatch_log_group" "apache_error" {
  name              = "/cloud-ops-lab/ec2/apache/error"
  retention_in_days = 30

  tags = {
    Project = var.project_name
    Phase   = "10"
  }
}

# ── メトリクスフィルター ──────────────────────────────
resource "aws_cloudwatch_log_metric_filter" "apache_error_count" {
  name           = "ApacheErrorCount"
  log_group_name = aws_cloudwatch_log_group.apache_error.name
  pattern        = "[severity=\"*error*\", ...]"

  metric_transformation {
    name          = "ApacheErrorCount"
    namespace     = "CloudOpsLab/Apache"
    value         = "1"
    default_value = "0"
  }
}

# ── CloudWatch アラーム ───────────────────────────────
data "aws_sns_topic" "alert" {
  name = "cloud-ops-lab-site-alert"
}

resource "aws_cloudwatch_metric_alarm" "apache_error_alert" {
  alarm_name          = "ApacheErrorAlert"
  alarm_description   = "Apache error log detected"
  metric_name         = "ApacheErrorCount"
  namespace           = "CloudOpsLab/Apache"
  statistic           = "Sum"
  period              = 300
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [data.aws_sns_topic.alert.arn]

  tags = {
    Project = var.project_name
    Phase   = "10"
  }
}
