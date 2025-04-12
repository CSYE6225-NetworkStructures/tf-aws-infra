provider "aws" {
  region = var.aws_region
  # Use the profile if it's specified and valid, otherwise use access/secret keys
  profile    = try(var.aws_profile, null) != "" ? var.aws_profile : null
  access_key = try(var.aws_profile, null) == "" ? var.aws_access_key : null
  secret_key = try(var.aws_profile, null) == "" ? var.aws_secret_key : null
}

# Get the current AWS account ID
data "aws_caller_identity" "current" {}

# Random UUID for S3 bucket and other resources
resource "random_uuid" "resource_uuid" {}

# Generate random password for database
resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Generate a shorter identifier for resource names
locals {
  resource_suffix = substr(random_uuid.resource_uuid.result, 0, 8)
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

  # Create lowercase versions for DB resources that have naming restrictions
  lowercase_vpc_name = "vpc${local.existing_vpc_count}${local.resource_suffix}"

  # Select the first 3 AZs dynamically
  availability_zones = slice(data.aws_availability_zones.available.names, 0, var.subnet_count)

  # Generate Subnet CIDRs Dynamically
  public_subnet_cidrs  = [for i in range(var.subnet_count) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnet_cidrs = [for i in range(var.subnet_count) : cidrsubnet(var.vpc_cidr, 8, i + var.subnet_count)]

  # Generate S3 bucket name with UUID
  bucket_name = "csye6225-${random_uuid.resource_uuid.result}"

  # Generate unique names for IAM resources
  iam_role_name     = "ec2-role-${local.resource_suffix}"
  iam_policy_prefix = "policy-${local.resource_suffix}"
  iam_profile_name  = "ec2-profile-${local.resource_suffix}"

  # DB resource names
  db_subnet_group_name    = "db-subnet-group-${local.resource_suffix}"
  db_parameter_group_name = "db-param-group-${local.resource_suffix}"
  db_identifier           = "csye6225-${local.resource_suffix}"

  # Load balancer and autoscaling names
  lb_name              = "app-lb-${local.resource_suffix}"
  lb_tg_name           = "app-lb-tg-${local.resource_suffix}"
  asg_name             = "csye6225-asg-${local.resource_suffix}"
  launch_template_name = "csye6225_asg"

  # KMS key names
  kms_ec2_alias     = "alias/ec2-key-${local.resource_suffix}"
  kms_rds_alias     = "alias/rds-key-${local.resource_suffix}"
  kms_s3_alias      = "alias/s3-key-${local.resource_suffix}"
  kms_secrets_alias = "alias/secrets-key-${local.resource_suffix}"

  # Secret name for database password
  db_secret_name = "db-password-${local.resource_suffix}"
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
# Create KMS Key for EC2 with least privilege
resource "aws_kms_key" "ec2_key" {
  description             = "KMS key for EC2 encryption"
  enable_key_rotation     = true
  rotation_period_in_days = 90
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17",
    Id      = "key-ec2-policy",
    Statement = [
      {
        Sid    = "Enable Key Admin Permissions",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        Action   = "kms:*",
        Resource = "*"
      },
      {
        Sid    = "Allow service-linked role use of the customer managed key",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.iam_role_name}"
        },
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ],
        Resource = "*"
      },
      {
        Sid    = "Allow attachment of persistent resources",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = [
          "kms:CreateGrant",
          "kms:ListGrants",
          "kms:RevokeGrant"
        ],
        Resource = "*",
        Condition = {
          Bool = {
            "kms:GrantIsForAWSResource" : "true"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${local.unique_vpc_name}-EC2-KMS-Key"
  }
}

resource "aws_kms_alias" "ec2_key_alias" {
  name          = local.kms_ec2_alias
  target_key_id = aws_kms_key.ec2_key.key_id
}

# KMS Key for RDS with least privilege
resource "aws_kms_key" "rds_key" {
  description             = "KMS key for RDS encryption"
  enable_key_rotation     = true
  rotation_period_in_days = 90
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "Enable Key Admin Permissions",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        Action   = "kms:*",
        Resource = "*"
      },
      {
        Sid    = "Allow RDS service to use the key",
        Effect = "Allow",
        Principal = {
          Service = "rds.amazonaws.com"
        },
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource = "*"
      },
      {
        Sid    = "Allow EC2 role to decrypt",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.iam_role_name}"
        },
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ],
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${local.unique_vpc_name}-RDS-KMS-Key"
  }
}

resource "aws_kms_alias" "rds_key_alias" {
  name          = local.kms_rds_alias
  target_key_id = aws_kms_key.rds_key.key_id
}

# KMS Key for S3 with least privilege
resource "aws_kms_key" "s3_key" {
  description             = "KMS key for S3 encryption"
  enable_key_rotation     = true
  rotation_period_in_days = 90
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "Enable Key Admin Permissions",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        Action   = "kms:*",
        Resource = "*"
      },
      {
        Sid    = "Allow S3 service to use the key",
        Effect = "Allow",
        Principal = {
          Service = "s3.amazonaws.com"
        },
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource = "*"
      },
      {
        Sid    = "Allow EC2 role to use the key for S3 access",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.iam_role_name}"
        },
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${local.unique_vpc_name}-S3-KMS-Key"
  }
}

resource "aws_kms_alias" "s3_key_alias" {
  name          = local.kms_s3_alias
  target_key_id = aws_kms_key.s3_key.key_id
}

# KMS Key for Secrets Manager with proper service permissions
resource "aws_kms_key" "secrets_key" {
  description             = "KMS key for Secrets Manager encryption"
  enable_key_rotation     = true
  rotation_period_in_days = 90
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "Enable Key Admin Permissions",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        Action   = "kms:*",
        Resource = "*"
      },
      {
        Sid    = "Allow Secrets Manager service to use the key",
        Effect = "Allow",
        Principal = {
          AWS = "*"
        },
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource = "*"
      },
      {
        Sid    = "Allow EC2 role to decrypt specific secrets",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.iam_role_name}"
        },
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ],
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${local.unique_vpc_name}-Secrets-KMS-Key"
  }
}

resource "aws_kms_alias" "secrets_key_alias" {
  name          = local.kms_secrets_alias
  target_key_id = aws_kms_key.secrets_key.key_id
}

# Create AWS Secrets Manager secret for database password
resource "aws_secretsmanager_secret" "db_password" {
  name                    = local.db_secret_name
  kms_key_id              = aws_kms_key.secrets_key.arn
  recovery_window_in_days = 7

  tags = {
    Name = "${local.unique_vpc_name}-DB-Password-Secret"
  }
}

# Create Secret Version with database credentials
resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    username = "root"
    password = random_password.db_password.result
    engine   = var.db_engine
    host     = aws_db_instance.db_instance.address
    port     = aws_db_instance.db_instance.port
    dbname   = aws_db_instance.db_instance.db_name
  })

  depends_on = [aws_db_instance.db_instance]
}

# Load Balancer Security Group
resource "aws_security_group" "lb_sg" {
  vpc_id = aws_vpc.main.id
  name   = "${local.unique_vpc_name}-LB-SG"

  # Allow HTTPS traffic (port 443)
  ingress {
    from_port   = 443
    to_port     = 443
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
    Name = "${local.unique_vpc_name}-LoadBalancer-SG"
  }
}

# Updated Application Security Group - Only allow traffic from Load Balancer, not direct access
resource "aws_security_group" "application_sg" {
  vpc_id = aws_vpc.main.id

  # SSH access - only from allowed IPs if needed for administration
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidrs
  }

  # App port access from load balancer only
  ingress {
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.lb_sg.id]
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

# Create S3 Bucket with UUID name and encryption using KMS
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

# Enable default encryption for S3 Bucket using KMS
resource "aws_s3_bucket_server_side_encryption_configuration" "app_bucket_encryption" {
  bucket = aws_s3_bucket.app_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_key.arn
      sse_algorithm     = "aws:kms"
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
  name       = local.db_subnet_group_name
  subnet_ids = aws_subnet.private_subnets[*].id

  tags = {
    Name = "${local.unique_vpc_name}-DB-Subnet-Group"
  }
}

# Create RDS Parameter Group
resource "aws_db_parameter_group" "db_parameter_group" {
  name   = local.db_parameter_group_name
  family = var.db_parameter_group_family

  tags = {
    Name = "${local.unique_vpc_name}-DB-Parameter-Group"
  }
}

# Create RDS Instance with KMS encryption
resource "aws_db_instance" "db_instance" {
  identifier             = local.db_identifier
  allocated_storage      = 20
  storage_type           = "gp2"
  engine                 = var.db_engine
  engine_version         = var.db_engine_version
  instance_class         = var.db_instance_class
  db_name                = "health_check"
  username               = "root"
  password               = random_password.db_password.result # Use generated password directly
  parameter_group_name   = aws_db_parameter_group.db_parameter_group.name
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.database_sg.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
  multi_az               = false
  deletion_protection    = false

  # Enable storage encryption with KMS
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds_key.arn

  tags = {
    Name = "${local.unique_vpc_name}-RDS-Instance"
  }

  # This is important to ensure it can be deleted and recreated
  lifecycle {
    create_before_destroy = true
  }
}

# Application Load Balancer
resource "aws_lb" "app_lb" {
  name               = local.lb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = aws_subnet.public_subnets[*].id

  enable_deletion_protection = false

  tags = {
    Name = "${local.unique_vpc_name}-ALB"
  }
}

# Target Group for Load Balancer
resource "aws_lb_target_group" "app_tg" {
  name     = local.lb_tg_name
  port     = var.app_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    interval            = 60
    path                = "/"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    matcher             = "200-399"
  }

  tags = {
    Name = "${local.unique_vpc_name}-TG"
  }
}

# HTTPS Listener for Load Balancer using imported certificate
resource "aws_lb_listener" "app_listener_https" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = data.aws_acm_certificate.imported_cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "app_asg" {
  name                      = local.asg_name
  min_size                  = 3
  max_size                  = 5
  desired_capacity          = 3
  vpc_zone_identifier       = aws_subnet.public_subnets[*].id
  target_group_arns         = [aws_lb_target_group.app_tg.arn]
  health_check_grace_period = 300
  health_check_type         = "ELB"

  launch_template {
    id      = aws_launch_template.app_launch_template.id
    version = "$Latest"
  }

  default_cooldown = 60

  tag {
    key                 = "Name"
    value               = "${local.unique_vpc_name}-ASG"
    propagate_at_launch = true
  }

  depends_on = [aws_lb_target_group.app_tg]

  # Add a lifecycle block to ignore changes to desired_capacity
  lifecycle {
    ignore_changes = [desired_capacity, target_group_arns]
  }
}

# Scale up policy when average CPU usage is above 5%
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "${local.asg_name}-scale-up"
  autoscaling_group_name = aws_autoscaling_group.app_asg.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 60
  policy_type            = "SimpleScaling"
}

# Scale down policy when average CPU usage is below 3%
resource "aws_autoscaling_policy" "scale_down" {
  name                   = "${local.asg_name}-scale-down"
  autoscaling_group_name = aws_autoscaling_group.app_asg.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 60
  policy_type            = "SimpleScaling"
}

# CloudWatch Alarm for High CPU to trigger scale up
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${local.asg_name}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 5 # 5% CPU utilization

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app_asg.name
  }

  alarm_description = "Scale up if CPU exceeds 5% for 2 consecutive periods of 120 seconds"
  alarm_actions     = [aws_autoscaling_policy.scale_up.arn]
}

# CloudWatch Alarm for Low CPU to trigger scale down
resource "aws_cloudwatch_metric_alarm" "low_cpu" {
  alarm_name          = "${local.asg_name}-low-cpu"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 3 # 3% CPU utilization

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app_asg.name
  }

  alarm_description = "Scale down if CPU is below 3% for 2 consecutive periods of 120 seconds"
  alarm_actions     = [aws_autoscaling_policy.scale_down.arn]
}

# Route53 Record to point to the Load Balancer
resource "aws_route53_record" "app_dns" {
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.app_lb.dns_name
    zone_id                = aws_lb.app_lb.zone_id
    evaluate_target_health = true
  }
}

# Output the actual secret ARN for debugging purposes
output "db_secret_arn" {
  value       = aws_secretsmanager_secret.db_password.arn
  description = "The ARN of the database password secret"
}

# Output the role name for debugging purposes
output "ec2_role_name" {
  value       = aws_iam_role.ec2_s3_access_role.name
  description = "The name of the EC2 IAM role"
}

# Remove the standalone EC2 instance as it's replaced by the ASG
# resource "aws_instance" "web" {
#   ami                    = var.ami_id
#   instance_type          = "t2.micro"
#   subnet_id              = aws_subnet.public_subnets[0].id
#   vpc_security_group_ids = [aws_security_group.application_sg.id]
#   key_name               = var.key_name
#   iam_instance_profile   = aws_iam_instance_profile.ec2_instance_profile.name

#   user_data = base64encode(templatefile(var.user_data_script_path, {
#     DB_HOST        = aws_db_instance.db_instance.address
#     DB_PORT        = aws_db_instance.db_instance.port
#     DB_USER        = aws_db_instance.db_instance.username
#     DB_PASSWORD    = var.db_password
#     DB_NAME        = aws_db_instance.db_instance.db_name
#     PORT           = var.app_port
#     AWS_REGION     = var.aws_region
#     S3_BUCKET_NAME = aws_s3_bucket.app_bucket.bucket
#   }))

#   user_data_replace_on_change = true

#   root_block_device {
#     volume_size           = 25
#     volume_type           = "gp2"
#     delete_on_termination = true
#   }

#   disable_api_termination = false

#   tags = {
#     Name = "${local.unique_vpc_name}-Web-Instance"
#   }

#   depends_on = [aws_db_instance.db_instance, aws_s3_bucket.app_bucket]
# }

# Make sure we have the AutoScaling Service-Linked Role
resource "aws_iam_service_linked_role" "autoscaling" {
  aws_service_name = "autoscaling.amazonaws.com"
  description      = "Default Service-Linked Role enables access to AWS Services and Resources used or managed by Auto Scaling"
  # This role is automatically created by AWS if it doesn't exist already
  # We're explicitly creating it to ensure it exists before the ASG is created
  count = 0 # Set to 0 since it's likely already created, but change to 1 if needed
}

# Create IAM Role for EC2 to access S3 and Secrets Manager
resource "aws_iam_role" "ec2_s3_access_role" {
  name = local.iam_role_name

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

  # This ensures the role can be recreated if needed
  lifecycle {
    create_before_destroy = true
  }
}

# Create IAM Policy for S3 Access
resource "aws_iam_policy" "s3_access_policy" {
  name        = "${local.iam_policy_prefix}-s3-access"
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

  lifecycle {
    create_before_destroy = true
  }
}

# Create IAM Policy for RDS Access
resource "aws_iam_policy" "ec2_rds_access_policy" {
  name        = "${local.iam_policy_prefix}-rds-access"
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

  lifecycle {
    create_before_destroy = true
  }
}

# Create Secrets Manager Access Policy with FIXED permissions
resource "aws_iam_policy" "secrets_manager_policy" {
  name        = "${local.iam_policy_prefix}-secrets-access"
  description = "Policy to allow EC2 access to Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ],
        Effect   = "Allow",
        Resource = aws_secretsmanager_secret.db_password.arn
      },
      {
        Action = [
          "secretsmanager:ListSecrets"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Create comprehensive KMS Access Policy with all required permissions
resource "aws_iam_policy" "ec2_decrypt_policy" {
  name        = "${local.iam_policy_prefix}-ec2-decrypt"
  description = "Policy to allow EC2 to decrypt volumes and other KMS operations"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "kms:CreateGrant",
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*",
          "kms:ListGrants"
        ],
        Resource = "*"
      }
    ]
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Create CloudWatch IAM Policy
resource "aws_iam_policy" "cloudwatch_policy" {
  name        = "${local.iam_policy_prefix}-cloudwatch"
  description = "Policy to allow EC2 to send logs and metrics to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:PutMetricAlarm",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:DescribeAlarmsForMetric"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Create Autoscaling IAM Policy
resource "aws_iam_policy" "autoscaling_policy" {
  name        = "${local.iam_policy_prefix}-autoscaling"
  description = "Policy to allow EC2 to work with autoscaling"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })

  lifecycle {
    create_before_destroy = true
  }
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

# Attach Secrets Manager Policy to EC2 Role
resource "aws_iam_role_policy_attachment" "secrets_policy_attachment" {
  role       = aws_iam_role.ec2_s3_access_role.name
  policy_arn = aws_iam_policy.secrets_manager_policy.arn
}

# Attach KMS Decrypt Policy to EC2 Role
resource "aws_iam_role_policy_attachment" "decrypt_policy_attachment" {
  role       = aws_iam_role.ec2_s3_access_role.name
  policy_arn = aws_iam_policy.ec2_decrypt_policy.arn
}

# Attach AWS Managed SSM Policy to allow management via Systems Manager
resource "aws_iam_role_policy_attachment" "ssm_policy_attachment" {
  role       = aws_iam_role.ec2_s3_access_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Attach CloudWatch Policy to EC2 Role
resource "aws_iam_role_policy_attachment" "cloudwatch_policy_attachment" {
  role       = aws_iam_role.ec2_s3_access_role.name
  policy_arn = aws_iam_policy.cloudwatch_policy.arn
}

# Attach AWS Managed CloudWatch Agent Policy
resource "aws_iam_role_policy_attachment" "cloudwatch_agent_policy_attachment" {
  role       = aws_iam_role.ec2_s3_access_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Attach Autoscaling Policy to EC2 Role
resource "aws_iam_role_policy_attachment" "autoscaling_policy_attachment" {
  role       = aws_iam_role.ec2_s3_access_role.name
  policy_arn = aws_iam_policy.autoscaling_policy.arn
}

# Create IAM Instance Profile
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = local.iam_profile_name
  role = aws_iam_role.ec2_s3_access_role.name

  lifecycle {
    create_before_destroy = true
  }
}

# Reference the imported SSL certificate
data "aws_acm_certificate" "imported_cert" {
  domain   = var.domain_name
  statuses = ["ISSUED"]
}

# Launch Template for Auto Scaling Group with EBS encryption using default AWS KMS key
resource "aws_launch_template" "app_launch_template" {
  name                   = local.launch_template_name
  image_id               = var.ami_id
  instance_type          = "t2.micro"
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.application_sg.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_instance_profile.name
  }

  user_data = base64encode(templatefile(var.user_data_script_path, {
    DB_SECRET_ARN  = aws_secretsmanager_secret.db_password.arn
    PORT           = var.app_port
    AWS_REGION     = var.aws_region
    S3_BUCKET_NAME = aws_s3_bucket.app_bucket.bucket
  }))

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = 25
      volume_type           = "gp2"
      delete_on_termination = true
      encrypted             = true
      # Use the default AWS managed key instead of our custom key to avoid permission issues
      # kms_key_id            = aws_kms_key.ec2_key.arn
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${local.unique_vpc_name}-ASG-Instance"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}