provider "aws" {
  region = var.aws_region
  # Use the profile if it's specified and valid, otherwise use access/secret keys
  profile    = try(var.aws_profile, null) != "" ? var.aws_profile : null
  access_key = try(var.aws_profile, null) == "" ? var.aws_access_key : null
  secret_key = try(var.aws_profile, null) == "" ? var.aws_secret_key : null
}

# Random UUID for S3 bucket
resource "random_uuid" "s3_bucket_uuid" {}

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

  # Create lowercase versions for DB resources that have naming restrictions
  lowercase_vpc_name = "demovpc${local.existing_vpc_count}"

  # Select the first 3 AZs dynamically
  availability_zones = slice(data.aws_availability_zones.available.names, 0, var.subnet_count)

  # Generate Subnet CIDRs Dynamically
  public_subnet_cidrs  = [for i in range(var.subnet_count) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnet_cidrs = [for i in range(var.subnet_count) : cidrsubnet(var.vpc_cidr, 8, i + var.subnet_count)]

  # Generate S3 bucket name with UUID
  bucket_name = "csye6225-${random_uuid.s3_bucket_uuid.result}"
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

# Create S3 Bucket with UUID name
resource "aws_s3_bucket" "app_bucket" {
  bucket        = local.bucket_name
  force_destroy = true # Allow Terraform to delete the bucket even if it's not empty

  tags = {
    Name = "${local.unique_vpc_name}-S3-Bucket"
  }
}

# S3 Bucket Ownership Controls
resource "aws_s3_bucket_ownership_controls" "app_bucket_ownership" {
  bucket = aws_s3_bucket.app_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# S3 Bucket ACL
resource "aws_s3_bucket_acl" "app_bucket_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.app_bucket_ownership]
  bucket     = aws_s3_bucket.app_bucket.id
  acl        = "private"
}

# Enable default encryption for S3 Bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "app_bucket_encryption" {
  bucket = aws_s3_bucket.app_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Create S3 Lifecycle Policy
resource "aws_s3_bucket_lifecycle_configuration" "app_bucket_lifecycle" {
  bucket = aws_s3_bucket.app_bucket.id

  rule {
    id     = "transition-to-standard-ia"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}

# Create Database Security Group
resource "aws_security_group" "database_sg" {
  vpc_id = aws_vpc.main.id

  # Allow database traffic from application security group
  ingress {
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.application_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.unique_vpc_name}-Database-SG"
  }
}

# Create DB Subnet Group using private subnets
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "${local.lowercase_vpc_name}dbsubnetgroup"
  subnet_ids = aws_subnet.private_subnets[*].id

  tags = {
    Name = "${local.unique_vpc_name}-DB-Subnet-Group"
  }
}

# Create RDS Parameter Group
resource "aws_db_parameter_group" "db_parameter_group" {
  name   = "${local.lowercase_vpc_name}dbparamgroup"
  family = var.db_parameter_group_family

  tags = {
    Name = "${local.unique_vpc_name}-DB-Parameter-Group"
  }
}

# Create RDS Instance
resource "aws_db_instance" "db_instance" {
  identifier             = "csye6225"
  allocated_storage      = 20
  storage_type           = "gp2"
  engine                 = var.db_engine
  engine_version         = var.db_engine_version
  instance_class         = var.db_instance_class
  db_name                = "health_check"
  username               = "root"
  password               = var.db_password
  parameter_group_name   = aws_db_parameter_group.db_parameter_group.name
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.database_sg.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
  multi_az               = false

  tags = {
    Name = "${local.unique_vpc_name}-RDS-Instance"
  }
}

# Create IAM Role for EC2 to access S3
resource "aws_iam_role" "ec2_s3_access_role" {
  name = "${local.lowercase_vpc_name}-ec2-s3-access-role"

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

  tags = {
    Name = "${local.unique_vpc_name}-EC2-S3-Access-Role"
  }
}

# Create IAM Policy for S3 Access
resource "aws_iam_policy" "s3_access_policy" {
  name        = "${local.lowercase_vpc_name}-s3-access-policy"
  description = "Policy to allow EC2 access to S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.app_bucket.arn,
          "${aws_s3_bucket.app_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Create IAM Policy for RDS Access
resource "aws_iam_policy" "ec2_rds_access_policy" {
  name        = "${local.lowercase_vpc_name}-ec2-rds-access-policy"
  description = "Policy to allow EC2 access to RDS instance"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeAddresses",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "rds:DescribeDBInstances",
          "rds:ListTagsForResource"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# Attach S3 Access Policy to EC2 Role
resource "aws_iam_role_policy_attachment" "s3_policy_attachment" {
  role       = aws_iam_role.ec2_s3_access_role.name
  policy_arn = aws_iam_policy.s3_access_policy.arn
}

# Attach RDS Access Policy to EC2 Role
resource "aws_iam_role_policy_attachment" "rds_policy_attachment" {
  role       = aws_iam_role.ec2_s3_access_role.name
  policy_arn = aws_iam_policy.ec2_rds_access_policy.arn
}

# Attach AWS Managed SSM Policy to allow management via Systems Manager
resource "aws_iam_role_policy_attachment" "ssm_policy_attachment" {
  role       = aws_iam_role.ec2_s3_access_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Create IAM Instance Profile
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "${local.lowercase_vpc_name}-ec2-instance-profile"
  role = aws_iam_role.ec2_s3_access_role.name
}

# EC2 Instance
resource "aws_instance" "web" {
  ami                    = var.ami_id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_subnets[0].id
  vpc_security_group_ids = [aws_security_group.application_sg.id]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2_instance_profile.name

  user_data = base64encode(templatefile(var.user_data_script_path, {
    DB_HOST        = aws_db_instance.db_instance.address
    DB_PORT        = aws_db_instance.db_instance.port
    DB_USER        = aws_db_instance.db_instance.username
    DB_PASSWORD    = var.db_password
    DB_NAME        = aws_db_instance.db_instance.db_name
    PORT           = var.app_port
    AWS_REGION     = var.aws_region
    S3_BUCKET_NAME = aws_s3_bucket.app_bucket.bucket
  }))

  user_data_replace_on_change = true

  root_block_device {
    volume_size           = 25
    volume_type           = "gp2"
    delete_on_termination = true
  }

  disable_api_termination = false

  tags = {
    Name = "${local.unique_vpc_name}-Web-Instance"
  }

  depends_on = [aws_db_instance.db_instance, aws_s3_bucket.app_bucket]
}