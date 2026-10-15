variable "name" {
  description = "Prefix for resource names."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "subnet_id" {
  description = "Private subnet for the host."
  type        = string
}

variable "instance_type" {
  description = "Instance type (Graviton by default)."
  type        = string
  default     = "t4g.micro"
}

variable "architecture" {
  description = "AMI architecture: arm64 for Graviton instance types, x86_64 otherwise."
  type        = string
  default     = "arm64"

  validation {
    condition     = contains(["arm64", "x86_64"], var.architecture)
    error_message = "architecture must be arm64 or x86_64."
  }
}

variable "root_volume_gb" {
  description = "Root volume size in GiB."
  type        = number
  default     = 20
}

variable "backup_tag_value" {
  description = "Value of the Backup tag that AWS Backup selects on."
  type        = string
  default     = "daily"
}

variable "tags" {
  description = "Extra tags for the instance."
  type        = map(string)
  default     = {}
}
