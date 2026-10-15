terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }

  # Partial configuration: bucket and region come from backend.hcl (local) or -backend-config (CI).
  backend "s3" {
    key          = "envs/dev/terraform.tfstate"
    encrypt      = true
    use_lockfile = true # S3-native state locking, no DynamoDB table needed
  }
}
