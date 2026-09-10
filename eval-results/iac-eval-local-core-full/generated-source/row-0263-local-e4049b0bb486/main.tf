terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_iam_user" "benchmark" {
  name = "iac-eval-ssh-user"
}

resource "aws_iam_user_ssh_key" "benchmark" {
  username   = aws_iam_user.benchmark.name
  encoding   = "SSH"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC7pL6M9Y3VJ2m7pOQeJmN2DcQzwx8Qw6YvK88N3Q0k6rZ3G8YTxJGe3T1ZQq4uQw8Zl0gx6sV4G1Q8zZ8L3b0LSEYvNqHXv5u6pXJezmL87Q5t7pR5mQwoxEw3s8AQfTnyjv5SlQwQ4Rru8Ym3D7jKlK6bBK0fGk6vtrcwJ9F6Ibrqq3QeR3cQ4qHx4tZVZgD9FfF0QqKyc8cOT3S7R3fN1e8P8exCyF2Wk4vAwvLdnXnGFLjYcL3y8y8bxwqGlC3r9zKq6Iop6dZWG7xSnFf/8rDz1cdm3YbkakC6Q5efYxZwe8y6Fo4JZ8m2YdkfP7FT iac-eval@example.com"
}
