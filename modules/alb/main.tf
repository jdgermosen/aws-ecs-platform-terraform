locals {
  https_enabled = var.certificate_arn != ""
}

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Public HTTP/HTTPS into the load balancer"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-alb" }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  # checkov:skip=CKV_AWS_260: public port 80 is required; it redirects to HTTPS when a certificate is set
  security_group_id = aws_security_group.alb.id
  description       = "HTTP (redirects to HTTPS when a certificate is set)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  count = local.https_enabled ? 1 : 0

  security_group_id = aws_security_group.alb.id
  description       = "HTTPS"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "to_targets" {
  security_group_id = aws_security_group.alb.id
  description       = "Only to targets inside the VPC on the app port"
  cidr_ipv4         = var.vpc_cidr_block
  ip_protocol       = "tcp"
  from_port         = var.target_port
  to_port           = var.target_port
}

resource "aws_lb" "this" {
  # checkov:skip=CKV_AWS_150: deletion protection is a variable (off in dev so the lab can be destroyed)
  # checkov:skip=CKV_AWS_91: access logs need a dedicated log bucket; enable for production
  # checkov:skip=CKV2_AWS_28: AWS WAF is optional (enable_waf) to keep the dev lab cheap
  # checkov:skip=CKV2_AWS_76: the optional WAF includes AWSManagedRulesKnownBadInputsRuleSet, which covers Log4j
  name                       = "${var.name}-alb"
  load_balancer_type         = "application"
  internal                   = false
  subnets                    = var.public_subnet_ids
  security_groups            = [aws_security_group.alb.id]
  drop_invalid_header_fields = true
  enable_deletion_protection = var.deletion_protection
  idle_timeout               = 60

  tags = { Name = "${var.name}-alb" }
}

resource "aws_lb_target_group" "app" {
  # checkov:skip=CKV_AWS_378: TLS terminates at the load balancer; targets sit in private subnets
  name                 = "${var.name}-app"
  port                 = var.target_port
  protocol             = "HTTP"
  target_type          = "ip" # required for Fargate tasks
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = var.health_check_path
    matcher             = "200-399"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
  }

  tags = { Name = "${var.name}-app" }
}

resource "aws_lb_listener" "http" {
  # checkov:skip=CKV_AWS_2: redirects to HTTPS whenever certificate_arn is set
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = local.https_enabled ? "redirect" : "forward"
    target_group_arn = local.https_enabled ? null : aws_lb_target_group.app.arn

    dynamic "redirect" {
      for_each = local.https_enabled ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }
}

resource "aws_lb_listener" "https" {
  count = local.https_enabled ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ---------------------------------------------------------------------------
# Optional AWS WAF: AWS managed rule groups plus a per-IP rate limit
# ---------------------------------------------------------------------------
locals {
  waf_managed_rules = {
    "AWSManagedRulesCommonRuleSet"          = 1
    "AWSManagedRulesKnownBadInputsRuleSet"  = 2
    "AWSManagedRulesAmazonIpReputationList" = 3
  }
}

resource "aws_wafv2_web_acl" "this" {
  # checkov:skip=CKV2_AWS_31: WAF request logging is left out to keep the optional WAF low-cost
  count = var.enable_waf ? 1 : 0

  name  = "${var.name}-alb"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  dynamic "rule" {
    for_each = local.waf_managed_rules
    content {
      name     = rule.key
      priority = rule.value

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = rule.key
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = rule.key
        sampled_requests_enabled   = true
      }
    }
  }

  rule {
    name     = "rate-limit-per-ip"
    priority = 10

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit-per-ip"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-alb"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "this" {
  count = var.enable_waf ? 1 : 0

  resource_arn = aws_lb.this.arn
  web_acl_arn  = aws_wafv2_web_acl.this[0].arn
}
