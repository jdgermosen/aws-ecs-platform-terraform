variable "name" {
  description = "Prefix for resource names."
  type        = string
}

variable "service_name" {
  description = "ECS service and container name."
  type        = string
  default     = "web"
}

variable "image" {
  description = "Container image to run."
  type        = string
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 80
}

variable "cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate task memory in MiB."
  type        = number
  default     = 512
}

variable "cpu_architecture" {
  description = "ARM64 (Graviton, cheaper) or X86_64. The image must support it."
  type        = string
  default     = "ARM64"

  validation {
    condition     = contains(["ARM64", "X86_64"], var.cpu_architecture)
    error_message = "cpu_architecture must be ARM64 or X86_64."
  }
}

variable "desired_count" {
  description = "Tasks to start with; autoscaling manages it afterwards."
  type        = number
  default     = 2
}

variable "min_capacity" {
  description = "Minimum tasks (keep at least 2 to cover both AZs)."
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Maximum tasks."
  type        = number
  default     = 4
}

variable "cpu_target_percent" {
  description = "Target average CPU utilisation for scaling."
  type        = number
  default     = 60
}

variable "environment" {
  description = "Plain environment variables for the container."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Container environment variables loaded from Secrets Manager: name => full secret ARN."
  type        = map(string)
  default     = {}
}

variable "enable_execute_command" {
  description = "Allow `aws ecs execute-command` into running tasks for debugging."
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the tasks."
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Load balancer security group allowed to reach the tasks."
  type        = string
}

variable "target_group_arn" {
  description = "Target group the service registers tasks with."
  type        = string
}

variable "log_retention_days" {
  description = "Retention for the application log group."
  type        = number
  default     = 30
}
