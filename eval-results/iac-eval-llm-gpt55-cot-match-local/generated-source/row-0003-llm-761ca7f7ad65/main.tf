terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

provider "aws" {
  alias  = "main"
  region = "us-west-1"
}

provider "aws" {
  alias  = "us-east"
  region = "us-east-1"
}

provider "aws" {
  alias  = "eu-central"
  region = "eu-central-1"
}

provider "aws" {
  alias  = "ap-southeast"
  region = "ap-southeast-1"
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "random_password" "db_password" {
  length  = 20
  special = false
}

data "aws_availability_zones" "main" {
  provider = aws.main
  state    = "available"
}

data "aws_availability_zones" "us_east" {
  provider = aws.us-east
  state    = "available"
}

data "aws_availability_zones" "eu_central" {
  provider = aws.eu-central
  state    = "available"
}

data "aws_availability_zones" "ap_southeast" {
  provider = aws.ap-southeast
  state    = "available"
}

resource "aws_route53_zone" "main" {
  provider = aws.main
  name     = "main"
}

# -------------------------
# us-west-1: Primary RDS
# -------------------------

resource "aws_vpc" "main" {
  provider             = aws.main
  cidr_block           = "10.10.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main-rds-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  provider = aws.main
  vpc_id   = aws_vpc.main.id

  tags = {
    Name = "main-rds-igw"
  }
}

resource "aws_subnet" "main_a" {
  provider                = aws.main
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.10.1.0/24"
  availability_zone       = data.aws_availability_zones.main.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "main-rds-subnet-a"
  }
}

resource "aws_subnet" "main_b" {
  provider                = aws.main
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.10.2.0/24"
  availability_zone       = data.aws_availability_zones.main.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "main-rds-subnet-b"
  }
}

resource "aws_route_table" "main" {
  provider = aws.main
  vpc_id   = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "main-rds-route-table"
  }
}

resource "aws_route_table_association" "main_a" {
  provider       = aws.main
  subnet_id      = aws_subnet.main_a.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "main_b" {
  provider       = aws.main
  subnet_id      = aws_subnet.main_b.id
  route_table_id = aws_route_table.main.id
}

resource "aws_security_group" "main_rds" {
  provider    = aws.main
  name        = "main-rds-sg-${random_id.suffix.hex}"
  description = "Allow MySQL access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "MySQL access"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "main" {
  provider   = aws.main
  name       = "main-db-subnet-group-${random_id.suffix.hex}"
  subnet_ids = [aws_subnet.main_a.id, aws_subnet.main_b.id]

  tags = {
    Name = "main-db-subnet-group"
  }
}

resource "aws_db_instance" "primary" {
  provider = aws.main

  identifier = "primary-${random_id.suffix.hex}"

  allocated_storage      = 20
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  db_name                = "maindb"
  username               = "adminuser"
  password               = random_password.db_password.result
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.main_rds.id]

  publicly_accessible      = true
  backup_retention_period  = 7
  skip_final_snapshot      = true
  deletion_protection      = false
  apply_immediately        = true
  auto_minor_version_upgrade = true

  tags = {
    Name = "primary"
  }
}

# -------------------------
# us-east-1: Replica
# -------------------------

resource "aws_vpc" "us_east" {
  provider             = aws.us-east
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "us-east-rds-vpc"
  }
}

resource "aws_internet_gateway" "us_east" {
  provider = aws.us-east
  vpc_id   = aws_vpc.us_east.id
}

resource "aws_subnet" "us_east_a" {
  provider                = aws.us-east
  vpc_id                  = aws_vpc.us_east.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = data.aws_availability_zones.us_east.names[0]
  map_public_ip_on_launch = true
}

resource "aws_subnet" "us_east_b" {
  provider                = aws.us-east
  vpc_id                  = aws_vpc.us_east.id
  cidr_block              = "10.20.2.0/24"
  availability_zone       = data.aws_availability_zones.us_east.names[1]
  map_public_ip_on_launch = true
}

resource "aws_route_table" "us_east" {
  provider = aws.us-east
  vpc_id   = aws_vpc.us_east.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.us_east.id
  }
}

resource "aws_route_table_association" "us_east_a" {
  provider       = aws.us-east
  subnet_id      = aws_subnet.us_east_a.id
  route_table_id = aws_route_table.us_east.id
}

resource "aws_route_table_association" "us_east_b" {
  provider       = aws.us-east
  subnet_id      = aws_subnet.us_east_b.id
  route_table_id = aws_route_table.us_east.id
}

resource "aws_security_group" "us_east_rds" {
  provider = aws.us-east
  name     = "us-east-rds-sg-${random_id.suffix.hex}"
  vpc_id   = aws_vpc.us_east.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "us_east" {
  provider   = aws.us-east
  name       = "us-east-db-subnet-group-${random_id.suffix.hex}"
  subnet_ids = [aws_subnet.us_east_a.id, aws_subnet.us_east_b.id]
}

resource "aws_db_instance" "replica_us_east" {
  provider = aws.us-east

  identifier             = "replica-us-east-${random_id.suffix.hex}"
  replicate_source_db    = aws_db_instance.primary.arn
  instance_class         = "db.t3.micro"
  db_subnet_group_name   = aws_db_subnet_group.us_east.name
  vpc_security_group_ids = [aws_security_group.us_east_rds.id]

  publicly_accessible        = true
  skip_final_snapshot        = true
  deletion_protection        = false
  apply_immediately          = true
  auto_minor_version_upgrade = true

  tags = {
    Name = "replica_us_east"
  }

  depends_on = [aws_db_instance.primary]
}

# -------------------------
# eu-central-1: Replica
# -------------------------

resource "aws_vpc" "eu_central" {
  provider             = aws.eu-central
  cidr_block           = "10.30.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "eu-central-rds-vpc"
  }
}

resource "aws_internet_gateway" "eu_central" {
  provider = aws.eu-central
  vpc_id   = aws_vpc.eu_central.id
}

resource "aws_subnet" "eu_central_a" {
  provider                = aws.eu-central
  vpc_id                  = aws_vpc.eu_central.id
  cidr_block              = "10.30.1.0/24"
  availability_zone       = data.aws_availability_zones.eu_central.names[0]
  map_public_ip_on_launch = true
}

resource "aws_subnet" "eu_central_b" {
  provider                = aws.eu-central
  vpc_id                  = aws_vpc.eu_central.id
  cidr_block              = "10.30.2.0/24"
  availability_zone       = data.aws_availability_zones.eu_central.names[1]
  map_public_ip_on_launch = true
}

resource "aws_route_table" "eu_central" {
  provider = aws.eu-central
  vpc_id   = aws_vpc.eu_central.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eu_central.id
  }
}

resource "aws_route_table_association" "eu_central_a" {
  provider       = aws.eu-central
  subnet_id      = aws_subnet.eu_central_a.id
  route_table_id = aws_route_table.eu_central.id
}

resource "aws_route_table_association" "eu_central_b" {
  provider       = aws.eu-central
  subnet_id      = aws_subnet.eu_central_b.id
  route_table_id = aws_route_table.eu_central.id
}

resource "aws_security_group" "eu_central_rds" {
  provider = aws.eu-central
  name     = "eu-central-rds-sg-${random_id.suffix.hex}"
  vpc_id   = aws_vpc.eu_central.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "eu_central" {
  provider   = aws.eu-central
  name       = "eu-central-db-subnet-group-${random_id.suffix.hex}"
  subnet_ids = [aws_subnet.eu_central_a.id, aws_subnet.eu_central_b.id]
}

resource "aws_db_instance" "replica_eu_central" {
  provider = aws.eu-central

  identifier             = "replica-eu-central-${random_id.suffix.hex}"
  replicate_source_db    = aws_db_instance.primary.arn
  instance_class         = "db.t3.micro"
  db_subnet_group_name   = aws_db_subnet_group.eu_central.name
  vpc_security_group_ids = [aws_security_group.eu_central_rds.id]

  publicly_accessible        = true
  skip_final_snapshot        = true
  deletion_protection        = false
  apply_immediately          = true
  auto_minor_version_upgrade = true

  tags = {
    Name = "replica_eu_central"
  }

  depends_on = [aws_db_instance.primary]
}

# -------------------------
# ap-southeast-1: Replica
# -------------------------

resource "aws_vpc" "ap_southeast" {
  provider             = aws.ap-southeast
  cidr_block           = "10.40.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "ap-southeast-rds-vpc"
  }
}

resource "aws_internet_gateway" "ap_southeast" {
  provider = aws.ap-southeast
  vpc_id   = aws_vpc.ap_southeast.id
}

resource "aws_subnet" "ap_southeast_a" {
  provider                = aws.ap-southeast
  vpc_id                  = aws_vpc.ap_southeast.id
  cidr_block              = "10.40.1.0/24"
  availability_zone       = data.aws_availability_zones.ap_southeast.names[0]
  map_public_ip_on_launch = true
}

resource "aws_subnet" "ap_southeast_b" {
  provider                = aws.ap-southeast
  vpc_id                  = aws_vpc.ap_southeast.id
  cidr_block              = "10.40.2.0/24"
  availability_zone       = data.aws_availability_zones.ap_southeast.names[1]
  map_public_ip_on_launch = true
}

resource "aws_route_table" "ap_southeast" {
  provider = aws.ap-southeast
  vpc_id   = aws_vpc.ap_southeast.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ap_southeast.id
  }
}

resource "aws_route_table_association" "ap_southeast_a" {
  provider       = aws.ap-southeast
  subnet_id      = aws_subnet.ap_southeast_a.id
  route_table_id = aws_route_table.ap_southeast.id
}

resource "aws_route_table_association" "ap_southeast_b" {
  provider       = aws.ap-southeast
  subnet_id      = aws_subnet.ap_southeast_b.id
  route_table_id = aws_route_table.ap_southeast.id
}

resource "aws_security_group" "ap_southeast_rds" {
  provider = aws.ap-southeast
  name     = "ap-southeast-rds-sg-${random_id.suffix.hex}"
  vpc_id   = aws_vpc.ap_southeast.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "ap_southeast" {
  provider   = aws.ap-southeast
  name       = "ap-southeast-db-subnet-group-${random_id.suffix.hex}"
  subnet_ids = [aws_subnet.ap_southeast_a.id, aws_subnet.ap_southeast_b.id]
}

resource "aws_db_instance" "replica_ap_southeast" {
  provider = aws.ap-southeast

  identifier             = "replica-ap-southeast-${random_id.suffix.hex}"
  replicate_source_db    = aws_db_instance.primary.arn
  instance_class         = "db.t3.micro"
  db_subnet_group_name   = aws_db_subnet_group.ap_southeast.name
  vpc_security_group_ids = [aws_security_group.ap_southeast_rds.id]

  publicly_accessible        = true
  skip_final_snapshot        = true
  deletion_protection        = false
  apply_immediately          = true
  auto_minor_version_upgrade = true

  tags = {
    Name = "replica_ap_southeast"
  }

  depends_on = [aws_db_instance.primary]
}

# -------------------------
# Route 53 Weighted Routing
# -------------------------

resource "aws_route53_record" "replica_us_east_weighted" {
  provider = aws.main

  zone_id = aws_route53_zone.main.zone_id
  name    = "db.main"
  type    = "CNAME"
  ttl     = 60

  set_identifier = "replica-us-east"

  weighted_routing_policy {
    weight = 33
  }

  records = [aws_db_instance.replica_us_east.address]
}

resource "aws_route53_record" "replica_eu_central_weighted" {
  provider = aws.main

  zone_id = aws_route53_zone.main.zone_id
  name    = "db.main"
  type    = "CNAME"
  ttl     = 60

  set_identifier = "replica-eu-central"

  weighted_routing_policy {
    weight = 33
  }

  records = [aws_db_instance.replica_eu_central.address]
}

resource "aws_route53_record" "replica_ap_southeast_weighted" {
  provider = aws.main

  zone_id = aws_route53_zone.main.zone_id
  name    = "db.main"
  type    = "CNAME"
  ttl     = 60

  set_identifier = "replica-ap-southeast"

  weighted_routing_policy {
    weight = 34
  }

  records = [aws_db_instance.replica_ap_southeast.address]
}

output "primary_endpoint" {
  value = aws_db_instance.primary.endpoint
}

output "weighted_database_dns_name" {
  value = aws_route53_record.replica_us_east_weighted.fqdn
}

output "replica_us_east_endpoint" {
  value = aws_db_instance.replica_us_east.endpoint
}

output "replica_eu_central_endpoint" {
  value = aws_db_instance.replica_eu_central.endpoint
}

output "replica_ap_southeast_endpoint" {
  value = aws_db_instance.replica_ap_southeast.endpoint
}