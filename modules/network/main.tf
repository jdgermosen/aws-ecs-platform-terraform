data "aws_availability_zones" "available" {
  # checkov:skip=CKV_AWS_394: only the first az_count zones are used, so new AZs never change the selection
  state = "available"

  # Regular AZs only (no opt-in Local Zones or Wavelength Zones); the module uses the first az_count.
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_region" "current" {}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # /16 VPC -> /20 subnets: public use netnums 0..n-1, private use 8..8+n-1
  public_cidrs  = [for i in range(var.az_count) : cidrsubnet(var.cidr_block, 4, i)]
  private_cidrs = [for i in range(var.az_count) : cidrsubnet(var.cidr_block, 4, i + 8)]

  interface_endpoints = var.enable_interface_endpoints ? toset([
    "ecr.api", "ecr.dkr", "logs", "ssm", "ssmmessages", "ec2messages", "secretsmanager",
  ]) : toset([])
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name}-vpc" }
}

# Lock down the default security group so nothing can use it by accident.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-default-deny" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-igw" }
}

resource "aws_subnet" "public" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.public_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = { Name = "${var.name}-public-${local.azs[count.index]}", Tier = "public" }
}

resource "aws_subnet" "private" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = { Name = "${var.name}-private-${local.azs[count.index]}", Tier = "private" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-public" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = var.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# One private route table per AZ so each AZ can use its own NAT gateway when nat_mode = "gateway".
resource "aws_route_table" "private" {
  count = var.az_count

  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-private-${local.azs[count.index]}" }
}

resource "aws_route_table_association" "private" {
  count = var.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ---------------------------------------------------------------------------
# Egress option 1: managed NAT gateway in every AZ (highly available, ~$33/month each + data)
# ---------------------------------------------------------------------------
resource "aws_eip" "nat" {
  count = var.nat_mode == "gateway" ? var.az_count : 0

  domain = "vpc"
  tags   = { Name = "${var.name}-nat-${local.azs[count.index]}" }
}

resource "aws_nat_gateway" "this" {
  count = var.nat_mode == "gateway" ? var.az_count : 0

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = { Name = "${var.name}-nat-${local.azs[count.index]}" }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route" "private_nat_gateway" {
  count = var.nat_mode == "gateway" ? var.az_count : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[count.index].id
}

# ---------------------------------------------------------------------------
# Egress option 2: a single Graviton NAT instance (~$3/month). Cheaper for dev and labs,
# but it is a single point of failure for outbound traffic, so it is not the production choice.
# ---------------------------------------------------------------------------
data "aws_ssm_parameter" "al2023_arm64" {
  count = var.nat_mode == "instance" ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "aws_security_group" "nat" {
  # checkov:skip=CKV_AWS_382: a NAT instance must forward any protocol to the internet
  count = var.nat_mode == "instance" ? 1 : 0

  name        = "${var.name}-nat-instance"
  description = "NAT instance: forward traffic from private subnets"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "All traffic from the private subnets"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = local.private_cidrs
  }

  egress {
    description = "Forward to the internet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-nat-instance" }
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# Session Manager access for troubleshooting; no SSH key pair is created.
resource "aws_iam_role" "nat" {
  count = var.nat_mode == "instance" ? 1 : 0

  name               = "${var.name}-nat-instance"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "nat_ssm" {
  count = var.nat_mode == "instance" ? 1 : 0

  role       = aws_iam_role.nat[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "nat" {
  count = var.nat_mode == "instance" ? 1 : 0

  name = "${var.name}-nat-instance"
  role = aws_iam_role.nat[0].name
}

resource "aws_instance" "nat" {
  # checkov:skip=CKV_AWS_88: a NAT instance needs a public IP to reach the internet
  # checkov:skip=CKV_AWS_126: basic 5-minute metrics are enough for the dev NAT instance
  count = var.nat_mode == "instance" ? 1 : 0

  ami                         = data.aws_ssm_parameter.al2023_arm64[0].value
  instance_type               = var.nat_instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.nat[0].id]
  iam_instance_profile        = aws_iam_instance_profile.nat[0].name
  associate_public_ip_address = true
  source_dest_check           = false
  ebs_optimized               = true
  user_data_replace_on_change = true

  user_data = <<-EOT
    #!/bin/bash
    set -euo pipefail
    dnf install -y iptables-services
    echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/90-nat.conf
    sysctl --system
    IFACE=$(ip route show default | awk '{print $5; exit}')
    iptables -t nat -A POSTROUTING -o "$IFACE" -s ${var.cidr_block} -j MASQUERADE
    iptables -F FORWARD
    service iptables save
    systemctl enable --now iptables
  EOT

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "${var.name}-nat-instance", Role = "nat" }

  lifecycle {
    ignore_changes = [ami]
  }
}

resource "aws_route" "private_nat_instance" {
  count = var.nat_mode == "instance" ? var.az_count : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat[0].primary_network_interface_id
}

# ---------------------------------------------------------------------------
# VPC endpoints: S3 gateway endpoint is free; interface endpoints cost ~$7/month per AZ each,
# so they are optional and keep AWS API traffic off the NAT path when enabled.
# ---------------------------------------------------------------------------
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = { Name = "${var.name}-s3" }
}

resource "aws_security_group" "endpoints" {
  count = var.enable_interface_endpoints ? 1 : 0

  name        = "${var.name}-vpc-endpoints"
  description = "HTTPS from inside the VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from the VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.cidr_block]
  }

  tags = { Name = "${var.name}-vpc-endpoints" }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoints

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints[0].id]
  private_dns_enabled = true

  tags = { Name = "${var.name}-${each.key}" }
}

# ---------------------------------------------------------------------------
# VPC flow logs for network forensics
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "flow_logs" {
  # checkov:skip=CKV_AWS_158: AWS-managed encryption is used; a customer-managed KMS key adds cost for a lab
  # checkov:skip=CKV_AWS_338: retention is a variable (30 days in dev) rather than a fixed year
  count = var.enable_flow_logs ? 1 : 0

  name              = "/vpc/${var.name}/flow-logs"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name               = "${var.name}-vpc-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json
}

data "aws_iam_policy_document" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["${aws_cloudwatch_log_group.flow_logs[0].arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name   = "write-flow-logs"
  role   = aws_iam_role.flow_logs[0].id
  policy = data.aws_iam_policy_document.flow_logs[0].json
}

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id          = aws_vpc.this.id
  traffic_type    = "ALL"
  log_destination = aws_cloudwatch_log_group.flow_logs[0].arn
  iam_role_arn    = aws_iam_role.flow_logs[0].arn
}
