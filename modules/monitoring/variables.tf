variable "name" {
  description = "Prefix for resource names."
  type        = string
}

variable "alert_email" {
  description = "Email that receives alarm notifications (confirm the SNS subscription email). Empty to skip."
  type        = string
  default     = ""
}

variable "alb_arn_suffix" {
  description = "Load balancer ARN suffix."
  type        = string
}

variable "target_group_arn_suffix" {
  description = "Target group ARN suffix."
  type        = string
}

variable "alb_5xx_threshold" {
  description = "Target 5xx responses in 5 minutes that trigger an alarm."
  type        = number
  default     = 10
}

variable "ecs_cluster_name" {
  description = "ECS cluster name."
  type        = string
}

variable "ecs_service_name" {
  description = "ECS service name."
  type        = string
}

variable "ops_host_instance_id" {
  description = "Ops host instance ID for status-check alarms. Empty to skip."
  type        = string
  default     = ""
}
