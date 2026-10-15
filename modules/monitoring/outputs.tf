output "alerts_topic_arn" {
  description = "SNS topic that receives alarm notifications."
  value       = aws_sns_topic.alerts.arn
}
