output "sns_topic_arn" {
  value = aws_sns_topic.site_alert.arn
}

output "lambda_function_name" {
  value = aws_lambda_function.site_monitor.function_name
}

output "monitor_url" {
  value = var.target_url
}
