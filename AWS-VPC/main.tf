provider "aws" {
  region = var.aws_region
  # Use the profile if it's specified and valid, otherwise use access/secret keys
  profile    = try(var.aws_profile, null) != "" ? var.aws_profile : null
  access_key = try(var.aws_profile, null) == "" ? var.aws_access_key : null
  secret_key = try(var.aws_profile, null) == "" ? var.aws_secret_key : null
}

# Fetch the first 3 availability zones for the selected region
data "aws_availability_zones" "available" {}

# Find existing VPCs with the "Demo-VPC" prefix
data "aws_vpcs" "existing_vpcs" {}

# Generate Unique VPC Name with Incrementing Counter
locals {
  base_vpc_name = "Demo-VPC"

  # Count how many existing VPCs start with "Demo-VPC"
  existing_vpc_count = length(data.aws_vpcs.existing_vpcs.ids) + 1

  # Generate a unique name by appending the counter
  unique_vpc_name = "${local.base_vpc_name}-${local.existing_vpc_count}"

  # Select the first 3 AZs dynamically
  availability_zones = slice(data.aws_availability_zones.available.names, 0, var.subnet_count)

  # Generate Subnet CIDRs Dynamically
  public_subnet_cidrs  = [for i in range(var.subnet_count) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnet_cidrs = [for i in range(var.subnet_count) : cidrsubnet(var.vpc_cidr, 8, i + var.subnet_count)]
}

# Create a uniquely named VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = local.unique_vpc_name
  }
}

# Create Public Subnets (1 per AZ)
resource "aws_subnet" "public_subnets" {
  count                   = var.subnet_count
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.unique_vpc_name}-Public-Subnet-${count.index}"
  }
}

# Create Private Subnets (1 per AZ)
resource "aws_subnet" "private_subnets" {
  count             = var.subnet_count
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = local.availability_zones[count.index]

  tags = {
    Name = "${local.unique_vpc_name}-Private-Subnet-${count.index}"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.unique_vpc_name}-Internet-Gateway"
  }
}

# Create Public Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "${local.unique_vpc_name}-Public-Route-Table"
  }
}

# Associate Public Subnets with Public Route Table
resource "aws_route_table_association" "public" {
  count          = var.subnet_count
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

# Create Private Route Table
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.unique_vpc_name}-Private-Route-Table"
  }
}

# Associate Private Subnets with Private Route Table
resource "aws_route_table_association" "private" {
  count          = var.subnet_count
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_rt.id
}


# Application Security Group
resource "aws_security_group" "application_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.unique_vpc_name}-Application-SG"
  }
}

# EC2 Instance
resource "aws_instance" "web" {
  ami                    = var.ami_id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_subnets[0].id
  vpc_security_group_ids = [aws_security_group.application_sg.id]
  key_name               = var.key_name

  root_block_device {
    volume_size           = 25
    volume_type           = "gp2"
    delete_on_termination = true
  }

  disable_api_termination = false

  tags = {
    Name = "${local.unique_vpc_name}-Web-Instance"
  }
}