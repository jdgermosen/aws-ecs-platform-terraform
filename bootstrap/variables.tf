variable "region" {
  description = "AWS region for the state bucket."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name used in resource names."
  type        = string
  default     = "ecs-platform"
}

variable "github_repository" {
  description = "GitHub repository allowed to deploy, as owner/name."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "Use the owner/name format, e.g. octocat/aws-ecs-platform-terraform."
  }
}

variable "apply_environments" {
  description = "GitHub environments whose jobs may assume the apply role."
  type        = list(string)
  default     = ["dev"]
}
