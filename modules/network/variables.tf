variable "name" {
  description = "Prefix for resource names."
  type        = string
}

variable "cidr_block" {
  description = "VPC CIDR block. Must be a /16 so it splits into /20 subnets."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrhost(var.cidr_block, 0)) && endswith(var.cidr_block, "/16")
    error_message = "cidr_block must be a valid /16 CIDR."
  }
}

variable "az_count" {
  description = "Number of Availability Zones to spread subnets across."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 4
    error_message = "Use between 2 and 4 Availability Zones (an ALB needs at least 2)."
  }
}

variable "nat_mode" {
  description = "Outbound internet for private subnets: \"gateway\" (managed NAT gateway per AZ) or \"instance\" (one low-cost NAT instance)."
  type        = string
  default     = "instance"

  validation {
    condition     = contains(["gateway", "instance"], var.nat_mode)
    error_message = "nat_mode must be \"gateway\" or \"instance\"."
  }
}

variable "nat_instance_type" {
  description = "Graviton instance type for the NAT instance."
  type        = string
  default     = "t4g.nano"
}

variable "enable_interface_endpoints" {
  description = "Create interface endpoints for ECR, CloudWatch Logs, SSM, and Secrets Manager."
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "Send VPC flow logs to CloudWatch Logs."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Retention for the flow log group."
  type        = number
  default     = 30
}
