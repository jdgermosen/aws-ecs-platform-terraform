variable "name" {
  description = "Prefix for resource names."
  type        = string
}

variable "vpc_id" {
  description = "VPC to create the load balancer in."
  type        = string
}

variable "vpc_cidr_block" {
  description = "VPC CIDR, used to scope load balancer egress to targets."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets in at least two AZs."
  type        = list(string)
}

variable "target_port" {
  description = "Port the application containers listen on."
  type        = number
  default     = 80
}

variable "health_check_path" {
  description = "Target group health check path."
  type        = string
  default     = "/"
}

variable "certificate_arn" {
  description = "ACM certificate ARN. When set, HTTPS is enabled and HTTP redirects to it."
  type        = string
  default     = ""
}

variable "deletion_protection" {
  description = "Protect the load balancer from accidental deletion."
  type        = bool
  default     = false
}

variable "enable_waf" {
  description = "Attach an AWS WAF web ACL (managed rules + per-IP rate limit). Adds roughly $10/month."
  type        = bool
  default     = false
}

variable "waf_rate_limit" {
  description = "Requests per 5 minutes from one IP before WAF blocks it."
  type        = number
  default     = 1000
}
