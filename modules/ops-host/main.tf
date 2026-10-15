data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-${var.architecture}"
}

# ---------------- IAM: managed through SSM only, no SSH keys ----------------
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name}-ops-host"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

data "aws_iam_policy_document" "ansible_transfer" {
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.ansible_transfer.arn}/*"]
  }
}

resource "aws_iam_role_policy" "ansible_transfer" {
  name   = "ansible-ssm-transfer"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.ansible_transfer.json
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.name}-ops-host"
  role = aws_iam_role.this.name
}

# ---------------- network: no inbound rules at all ----------------
resource "aws_security_group" "this" {
  name        = "${var.name}-ops-host"
  description = "Ops host: no inbound access; managed through SSM"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-ops-host" }
}

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.this.id
  description       = "HTTPS to SSM, CloudWatch, S3, and package repositories"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_instance" "this" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.this.id]
  iam_instance_profile   = aws_iam_instance_profile.this.name
  monitoring             = true
  ebs_optimized          = true

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_gb
    encrypted   = true
  }

  tags = merge(var.tags, {
    Name   = "${var.name}-ops-host"
    Role   = "ops"
    Backup = var.backup_tag_value
  })

  lifecycle {
    # Patch the running host with Ansible instead of replacing it on every new AMI.
    ignore_changes = [ami]
  }
}

# ---------------- S3 bucket Ansible's SSM connection uses for file transfer ----------------
resource "aws_s3_bucket" "ansible_transfer" {
  # Short-lived transfer files only (expired after a day), so these controls are not worth their cost:
  # checkov:skip=CKV_AWS_21: no versioning for temporary transfer objects
  # checkov:skip=CKV_AWS_18: no access logging for temporary transfer objects
  # checkov:skip=CKV_AWS_144: no cross-region replication for temporary transfer objects
  # checkov:skip=CKV_AWS_145: SSE-S3 keeps Ansible's presigned transfers simple
  # checkov:skip=CKV2_AWS_62: no event notifications needed
  bucket        = "${var.name}-ansible-ssm-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "ansible_transfer" {
  bucket                  = aws_s3_bucket.ansible_transfer.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ansible_transfer" {
  bucket = aws_s3_bucket.ansible_transfer.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "ansible_transfer" {
  bucket = aws_s3_bucket.ansible_transfer.id

  rule {
    id     = "expire-transfers"
    status = "Enabled"
    filter {}

    expiration {
      days = 1
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}
