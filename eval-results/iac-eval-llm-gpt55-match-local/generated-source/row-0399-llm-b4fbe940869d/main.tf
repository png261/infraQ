terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for created resources."
  type        = string
  default     = "oidc-alb-demo"
}

variable "oidc_authorization_endpoint" {
  description = "OIDC authorization endpoint."
  type        = string
  default     = "https://example.com/oauth2/authorize"
}

variable "oidc_token_endpoint" {
  description = "OIDC token endpoint."
  type        = string
  default     = "https://example.com/oauth2/token"
}

variable "oidc_user_info_endpoint" {
  description = "OIDC user info endpoint."
  type        = string
  default     = "https://example.com/oauth2/userInfo"
}

variable "oidc_issuer" {
  description = "OIDC issuer URL."
  type        = string
  default     = "https://example.com"
}

variable "oidc_client_id" {
  description = "OIDC client ID."
  type        = string
  default     = "replace-with-client-id"
}

variable "oidc_client_secret" {
  description = "OIDC client secret."
  type        = string
  sensitive   = true
  default     = "replace-with-client-secret"
}

variable "oidc_scope" {
  description = "OIDC scopes requested by the ALB."
  type        = string
  default     = "openid email profile"
}

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  name_suffix = "${var.project_name}-${random_id.suffix.hex}"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.40.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_suffix}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_suffix}-igw"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.40.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_suffix}-public-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.40.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_suffix}-public-b"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_suffix}-public-rt"
  }
}

resource "aws_route" "public_default_ipv4" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "alb" {
  name        = "${local.name_suffix}-alb-sg"
  description = "Allow public HTTP and HTTPS access to the Application Load Balancer."
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow HTTP from the internet."
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS from the internet."
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_suffix}-alb-sg"
  }
}

resource "tls_private_key" "alb_cert" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "alb_cert" {
  private_key_pem = tls_private_key.alb_cert.private_key_pem

  subject {
    common_name  = "oidc-alb-demo.local"
    organization = "OIDC ALB Demo"
  }

  validity_period_hours = 8760

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth"
  ]

  dns_names = [
    "oidc-alb-demo.local"
  ]
}

resource "aws_acm_certificate" "alb_cert" {
  private_key      = tls_private_key.alb_cert.private_key_pem
  certificate_body = tls_self_signed_cert.alb_cert.cert_pem

  tags = {
    Name = "${local.name_suffix}-self-signed-cert"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb" "main" {
  name               = substr(replace("${local.name_suffix}-alb", "_", "-"), 0, 32)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]

  subnets = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]

  enable_deletion_protection = false

  tags = {
    Name = "${local.name_suffix}-alb"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https_oidc" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.alb_cert.arn

  default_action {
    type  = "authenticate-oidc"
    order = 1

    authenticate_oidc {
      authorization_endpoint = var.oidc_authorization_endpoint
      token_endpoint         = var.oidc_token_endpoint
      user_info_endpoint     = var.oidc_user_info_endpoint
      issuer                 = var.oidc_issuer
      client_id              = var.oidc_client_id
      client_secret          = var.oidc_client_secret
      scope                  = var.oidc_scope

      session_cookie_name              = "AWSELBAuthSessionCookie"
      session_timeout                  = 604800
      on_unauthenticated_request       = "authenticate"
      authentication_request_extra_params = {
        prompt = "login"
      }
    }
  }

  default_action {
    type  = "fixed-response"
    order = 2

    fixed_response {
      content_type = "text/plain"
      message_body = "Authentication succeeded. This response was served by an Application Load Balancer after OIDC authentication."
      status_code  = "200"
    }
  }
}

output "load_balancer_dns_name" {
  description = "DNS name of the Application Load Balancer."
  value       = aws_lb.main.dns_name
}

output "https_url" {
  description = "HTTPS URL for the OIDC-authenticated ALB endpoint."
  value       = "https://${aws_lb.main.dns_name}"
}

output "http_url" {
  description = "HTTP URL that redirects to HTTPS."
  value       = "http://${aws_lb.main.dns_name}"
}