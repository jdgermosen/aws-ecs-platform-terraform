data "aws_region" "current" {}

resource "aws_ecs_cluster" "this" {
  name = "${var.name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

resource "aws_cloudwatch_log_group" "app" {
  # checkov:skip=CKV_AWS_158: AWS-managed encryption is used; a customer-managed KMS key adds cost for a lab
  # checkov:skip=CKV_AWS_338: retention is a variable (30 days in dev) rather than a fixed year
  name              = "/ecs/${var.name}/${var.service_name}"
  retention_in_days = var.log_retention_days
}

# ---------------- IAM ----------------
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Execution role: used by the ECS agent to pull the image and write logs.
resource "aws_iam_role" "execution" {
  name               = "${var.name}-${var.service_name}-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "read_secrets" {
  count = length(var.secrets) > 0 ? 1 : 0

  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = distinct(values(var.secrets))
  }
}

resource "aws_iam_role_policy" "read_secrets" {
  count = length(var.secrets) > 0 ? 1 : 0

  name   = "read-app-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.read_secrets[0].json
}

# Task role: what the application itself may call. Empty by default (least privilege).
resource "aws_iam_role" "task" {
  name               = "${var.name}-${var.service_name}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

# ---------------- networking ----------------
resource "aws_security_group" "service" {
  name        = "${var.name}-${var.service_name}"
  description = "ECS tasks: app port from the load balancer only"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-${var.service_name}" }
}

resource "aws_vpc_security_group_ingress_rule" "from_alb" {
  # checkov:skip=CKV_AWS_260: false positive; the source is the load balancer security group, not 0.0.0.0/0
  security_group_id            = aws_security_group.service.id
  description                  = "App port from the load balancer"
  referenced_security_group_id = var.alb_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
}

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.service.id
  description       = "HTTPS to AWS APIs and image registries"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# ---------------- task + service ----------------
resource "aws_ecs_task_definition" "this" {
  family                   = "${var.name}-${var.service_name}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  container_definitions = jsonencode([
    {
      name                   = var.service_name
      image                  = var.image
      essential              = true
      readonlyRootFilesystem = false
      portMappings           = [{ containerPort = var.container_port, protocol = "tcp" }]
      environment            = [for k, v in var.environment : { name = k, value = v }]
      secrets                = [for k, v in var.secrets : { name = k, valueFrom = v }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = var.service_name
        }
      }
    }
  ])
}

resource "aws_ecs_service" "this" {
  name                              = var.service_name
  cluster                           = aws_ecs_cluster.this.id
  task_definition                   = aws_ecs_task_definition.this.arn
  desired_count                     = var.desired_count
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 30
  enable_execute_command            = var.enable_execute_command
  propagate_tags                    = "SERVICE"

  # Rolling deploy that never drops below current capacity, and rolls back automatically
  # if new tasks fail their health checks.
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = var.service_name
    container_port   = var.container_port
  }

  lifecycle {
    # Let Application Auto Scaling own the running count after the first apply.
    ignore_changes = [desired_count]
  }
}

# ---------------- autoscaling ----------------
resource "aws_appautoscaling_target" "this" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.min_capacity
  max_capacity       = var.max_capacity
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.name}-${var.service_name}-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  resource_id        = aws_appautoscaling_target.this.resource_id
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = var.cpu_target_percent
    scale_in_cooldown  = 120
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
