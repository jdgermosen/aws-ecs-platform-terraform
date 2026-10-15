provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

locals {
  name = "${var.project}-${var.environment}"
}

module "network" {
  source = "../../modules/network"

  name                       = local.name
  cidr_block                 = var.vpc_cidr
  az_count                   = 2
  nat_mode                   = var.nat_mode
  enable_interface_endpoints = var.enable_interface_endpoints
}

module "alb" {
  source = "../../modules/alb"

  name              = local.name
  vpc_id            = module.network.vpc_id
  vpc_cidr_block    = module.network.vpc_cidr_block
  public_subnet_ids = module.network.public_subnet_ids
  target_port       = var.container_port
  health_check_path = var.health_check_path
  certificate_arn   = var.certificate_arn
  enable_waf        = var.enable_waf
}

module "web" {
  source = "../../modules/ecs-service"

  name                  = local.name
  service_name          = "web"
  image                 = var.app_image
  container_port        = var.container_port
  cpu_architecture      = "ARM64"
  desired_count         = 2
  min_capacity          = 2
  max_capacity          = 4
  vpc_id                = module.network.vpc_id
  private_subnet_ids    = module.network.private_subnet_ids
  alb_security_group_id = module.alb.security_group_id
  target_group_arn      = module.alb.target_group_arn
}

module "ops_host" {
  source = "../../modules/ops-host"

  name      = local.name
  vpc_id    = module.network.vpc_id
  subnet_id = module.network.private_subnet_ids[0]
}

module "backup" {
  source = "../../modules/backup"

  name           = local.name
  retention_days = 7
  force_destroy  = true # dev only: lets `terraform destroy` remove the vault
}

module "monitoring" {
  source = "../../modules/monitoring"

  name                    = local.name
  alert_email             = var.alert_email
  alb_arn_suffix          = module.alb.arn_suffix
  target_group_arn_suffix = module.alb.target_group_arn_suffix
  ecs_cluster_name        = module.web.cluster_name
  ecs_service_name        = module.web.service_name
  ops_host_instance_id    = module.ops_host.instance_id
}
