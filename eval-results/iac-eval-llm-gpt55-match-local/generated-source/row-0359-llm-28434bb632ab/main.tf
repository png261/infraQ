terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the Lightsail instance will be created."
  type        = string
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "Availability zone for the Lightsail instance."
  type        = string
  default     = "us-east-1a"
}

variable "instance_name" {
  description = "Name of the Lightsail instance."
  type        = string
  default     = "basic-lightsail-instance"
}

variable "blueprint_id" {
  description = "Lightsail blueprint ID for the instance image."
  type        = string
  default     = "amazon_linux_2"
}

variable "bundle_id" {
  description = "Lightsail bundle ID defining instance size."
  type        = string
  default     = "nano_3_0"
}

variable "static_ip_name" {
  description = "Name of the Lightsail static IP."
  type        = string
  default     = "basic-lightsail-static-ip"
}

resource "aws_lightsail_instance" "basic" {
  name              = var.instance_name
  availability_zone = var.availability_zone
  blueprint_id      = var.blueprint_id
  bundle_id         = var.bundle_id

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl enable httpd
    systemctl start httpd

    cat > /var/www/html/index.html <<HTML
    <!DOCTYPE html>
    <html>
      <head>
        <title>Amazon Lightsail</title>
      </head>
      <body>
        <h1>Hello from Amazon Lightsail!</h1>
        <p>This instance was provisioned using Terraform user data.</p>
      </body>
    </html>
    HTML
  EOF

  tags = {
    Name        = var.instance_name
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

resource "aws_lightsail_static_ip" "basic" {
  name = var.static_ip_name
}

resource "aws_lightsail_static_ip_attachment" "basic" {
  static_ip_name = aws_lightsail_static_ip.basic.name
  instance_name  = aws_lightsail_instance.basic.name
}

output "lightsail_instance_name" {
  description = "Name of the Lightsail instance."
  value       = aws_lightsail_instance.basic.name
}

output "lightsail_instance_public_ip" {
  description = "Public IP address assigned to the Lightsail instance."
  value       = aws_lightsail_static_ip.basic.ip_address
}

output "lightsail_instance_username" {
  description = "Default username for the Lightsail instance."
  value       = aws_lightsail_instance.basic.username
}

output "website_url" {
  description = "HTTP URL for the Lightsail instance."
  value       = "http://${aws_lightsail_static_ip.basic.ip_address}"
}