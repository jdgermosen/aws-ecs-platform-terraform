variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name used in resource names and tags."
  type        = string
  default     = "ecs-platform"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "VPC CIDR block (/16)."
  type        = string
  default     = "10.20.0.0/16"
}

variable "nat_mode" {
  description = "\"instance\" (low-cost NAT instance) or \"gateway\" (managed NAT gateway per AZ)."
  type        = string
  default     = "instance"
}

variable "enable_interface_endpoints" {
  description = "Create interface VPC endpoints (adds roughly $7/month per endpoint per AZ)."
  type        = bool
  default     = false
}

variable "app_image" {
  description = "Container image for the web service (must support ARM64)."
  type        = string
  default     = "public.ecr.aws/nginx/nginx:stable-alpine"
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 80
}

variable "health_check_path" {
  description = "Load balancer health check path."
  type        = string
  default     = "/"
}

variable "certificate_arn" {
  description = "Optional ACM certificate ARN to enable HTTPS on the load balancer."
  type        = string
  default     = ""
}

variable "alert_email" {
  description = "Optional email for CloudWatch alarm notifications."
  type        = string
  default     = ""
}

variable "enable_waf" {
  description = "Put AWS WAF in front of the load balancer (adds roughly $10/month)."
  type        = bool
  default     = false
}
