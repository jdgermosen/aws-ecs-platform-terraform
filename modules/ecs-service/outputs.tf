output "cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.this.name
}

output "service_name" {
  description = "ECS service name."
  value       = aws_ecs_service.this.name
}

output "task_role_arn" {
  description = "Task role ARN; attach application permissions here."
  value       = aws_iam_role.task.arn
}

output "log_group_name" {
  description = "CloudWatch log group for the containers."
  value       = aws_cloudwatch_log_group.app.name
}
