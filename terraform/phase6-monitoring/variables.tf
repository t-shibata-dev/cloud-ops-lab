variable "alert_email" {
  description = "Email address to receive alerts"
  type        = string
}

variable "target_url" {
  description = "URL to monitor"
  type        = string
  default     = "http://13.196.53.206/"
}

variable "schedule_expression" {
  description = "EventBridge schedule (cron or rate)"
  type        = string
  default     = "rate(5 minutes)"
}
