# One-time setup, applied by an administrator with local state:
#   - S3 bucket for remote Terraform state (versioned, encrypted, TLS-only, native S3 locking)
#   - GitHub Actions OIDC identity provider
#   - a read-only "plan" role for pull requests and an "apply" role limited to the protected environment

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  state_bucket = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}-${var.region}"
  repo         = var.github_repository
}

# ---------------- remote state bucket ----------------
resource "aws_s3_bucket" "state" {
  # checkov:skip=CKV_AWS_18: access logging needs a separate log bucket; versioning + CloudTrail cover the audit trail here
  # checkov:skip=CKV_AWS_144: single-region lab; versioning protects against bad writes
  # checkov:skip=CKV2_AWS_62: no event notifications needed for state
  bucket = local.state_bucket

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "state_tls_only" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state_tls_only.json
}

# ---------------- GitHub Actions OIDC ----------------
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Pull requests and pushes to main may run `terraform plan`.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${local.repo}:pull_request",
        "repo:${local.repo}:ref:refs/heads/main",
      ]
    }
  }
}

data "aws_iam_policy_document" "apply_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only jobs running in the protected GitHub environment (required reviewers) may apply.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for env in var.apply_environments : "repo:${local.repo}:environment:${env}"]
    }
  }
}

data "aws_iam_policy_document" "state_access" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    # Get/Put/Delete on state objects, including the .tflock files used for S3-native locking.
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }
}

resource "aws_iam_role" "plan" {
  name                 = "${var.project}-github-plan"
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan_read_only" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "terraform-state"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.state_access.json
}

resource "aws_iam_role" "apply" {
  name                 = "${var.project}-github-apply"
  assume_role_policy   = data.aws_iam_policy_document.apply_trust.json
  max_session_duration = 3600
}

# Broad on purpose for a lab account: Terraform creates IAM roles, networking, and compute.
# In a shared account, scope this down and add a permissions boundary.
resource "aws_iam_role_policy_attachment" "apply_admin" {
  # checkov:skip=CKV_AWS_274: deliberate for a single-purpose lab account; see the README for how to scope it down
  role       = aws_iam_role.apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
