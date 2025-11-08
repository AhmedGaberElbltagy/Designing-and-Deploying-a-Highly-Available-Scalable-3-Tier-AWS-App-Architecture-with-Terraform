terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.1"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "tls_private_key" "app_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "app_key_pair" {
  key_name   = var.key_name
  public_key = tls_private_key.app_key.public_key_openssh
}

resource "local_file" "private_key_pem" {
  content         = tls_private_key.app_key.private_key_pem
  filename        = "${var.key_name}.pem"
  file_permission = "0400"
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"

  vpc_name             = var.vpc_name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = data.aws_availability_zones.available.names
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs

  tags = var.common_tags
}



# IAM ROLE FOR EC2
resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}



resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}

# EC2 Module
module "ec2" {
  source = "./modules/ec2"

  instance_type         = var.instance_type
  key_name              = var.key_name
  private_subnet_ids    = module.vpc.private_subnet_ids
  public_subnet_ids     = module.vpc.public_subnet_ids
  web_security_group_id = module.vpc.web_security_group_id
  app_security_group_id = module.vpc.app_security_group_id
  availability_zones    = data.aws_availability_zones.available.names
  iam_instance_profile  = aws_iam_instance_profile.ec2_profile.name
  internal_app_tg_arn   = module.alb.internal_app_tg_arn
  internal_alb_dns_name = module.alb.internal_alb_dns_name
  web_target_group_arn  = module.alb.web_target_group_arn
  tags                  = var.common_tags
  app_code_path         = "${path.root}/code/backend"
  web_code_path         = "${path.root}/code/frontend"
}

# ALB Module
module "alb" {
  source = "./modules/alb"

  alb_name                         = "${var.project_name}-alb"
  web_target_group_name            = "${var.project_name}-web-tg"
  app_target_group_name            = "${var.project_name}-app-tg"
  vpc_id                           = module.vpc.vpc_id
  public_subnet_ids                = module.vpc.public_subnet_ids
  private_subnet_ids               = module.vpc.private_subnet_ids
  alb_security_group_id            = module.vpc.alb_security_group_id
  internal_alb_security_group_id   = module.vpc.internal_alb_security_group_id
  tags                             = var.common_tags
}


