variable "name" {
  description = "Prefix for resource names."
  type        = string
}

variable "schedule" {
  description = "Backup schedule (cron, UTC)."
  type        = string
  default     = "cron(0 5 * * ? *)"
}

variable "retention_days" {
  description = "Days to keep each recovery point."
  type        = number
  default     = 14
}

variable "tag_value" {
  description = "Resources tagged Backup=<tag_value> are included."
  type        = string
  default     = "daily"
}

variable "force_destroy" {
  description = "Allow `terraform destroy` to delete the vault with recovery points in it (dev only)."
  type        = bool
  default     = false
}
