output "app_url" {
  description = "URL of the web service."
  value       = "${var.certificate_arn != "" ? "https" : "http"}://${module.alb.dns_name}"
}

output "ecs_cluster" {
  description = "ECS cluster name."
  value       = module.web.cluster_name
}

output "ops_host_instance_id" {
  description = "Ops host instance ID (Ansible target; `aws ssm start-session --target <id>`)."
  value       = module.ops_host.instance_id
}

output "ansible_ssm_bucket" {
  description = "Bucket to set as ansible_aws_ssm_bucket_name."
  value       = module.ops_host.ansible_transfer_bucket
}

output "alerts_topic_arn" {
  description = "SNS topic for alarms."
  value       = module.monitoring.alerts_topic_arn
}
