output "dns_name" {
  description = "Public DNS name of the load balancer."
  value       = aws_lb.this.dns_name
}

output "security_group_id" {
  description = "Load balancer security group ID."
  value       = aws_security_group.alb.id
}

output "target_group_arn" {
  description = "Target group for the application service."
  value       = aws_lb_target_group.app.arn
}

output "arn_suffix" {
  description = "Load balancer ARN suffix, for CloudWatch metrics."
  value       = aws_lb.this.arn_suffix
}

output "target_group_arn_suffix" {
  description = "Target group ARN suffix, for CloudWatch metrics."
  value       = aws_lb_target_group.app.arn_suffix
}

output "listener_arn" {
  description = "The listener that forwards to the app (HTTPS when enabled, otherwise HTTP)."
  value       = var.certificate_arn != "" ? aws_lb_listener.https[0].arn : aws_lb_listener.http.arn
}
