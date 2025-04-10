output "database_sg_id" {
  value       = aws_security_group.database_sg.id
  description = "The ID of the database security group"
}

output "aws_region" {
  value       = var.aws_region
  description = "The AWS region where resources are deployed"
}

output "availability_zones" {
  value       = local.availability_zones
  description = "The availability zones used for subnets"
}

output "db_port" {
  value       = aws_db_instance.db_instance.port
  description = "The port of the database"
}

output "db_name" {
  value       = aws_db_instance.db_instance.db_name
  description = "The name of the database"
}

output "db_username" {
  value       = aws_db_instance.db_instance.username
  description = "The master username of the database"
}

output "s3_bucket_arn" {
  value       = aws_s3_bucket.app_bucket.arn
  description = "The ARN of the S3 bucket"
}

output "kms_keys" {
  value = {
    ec2_key_arn     = aws_kms_key.ec2_key.arn
    rds_key_arn     = aws_kms_key.rds_key.arn
    s3_key_arn      = aws_kms_key.s3_key.arn
    secrets_key_arn = aws_kms_key.secrets_key.arn
  }
  description = "The ARNs of the KMS keys"
}

output "secrets_manager_arn" {
  value       = aws_secretsmanager_secret.db_password.arn
  description = "The ARN of the Secrets Manager secret storing the DB password"
}

output "vpc_id" {
  value       = aws_vpc.main.id
  description = "The ID of the VPC"
}

output "vpc_name" {
  value       = local.unique_vpc_name
  description = "The name of the VPC"
}

output "public_subnet_ids" {
  value       = aws_subnet.public_subnets[*].id
  description = "The IDs of the public subnets"
}

output "private_subnet_ids" {
  value       = aws_subnet.private_subnets[*].id
  description = "The IDs of the private subnets"
}

output "application_sg_id" {
  value       = aws_security_group.application_sg.id
  description = "The ID of the application security group"
}

output "db_endpoint" {
  value       = aws_db_instance.db_instance.address
  description = "The endpoint of the database"
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.app_bucket.bucket
  description = "The name of the S3 bucket"
}

output "certificate_arn" {
  value       = data.aws_acm_certificate.imported_cert.arn
  description = "The ARN of the imported SSL certificate"
}

output "terraform_state_key" {
  value       = "terraform-${var.aws_region}-${replace(var.vpc_cidr, "/", "-")}.tfstate"
  description = "Suggested key for terraform state"
}

# Load Balancer outputs
output "auto_scaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.app_asg.name
}

output "auto_scaling_group_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.app_asg.arn
}

output "launch_template_id" {
  description = "ID of the Launch Template"
  value       = aws_launch_template.app_launch_template.id
}

output "load_balancer_dns" {
  description = "The DNS name of the load balancer"
  value       = aws_lb.app_lb.dns_name
}

output "load_balancer_arn" {
  description = "ARN of the Load Balancer"
  value       = aws_lb.app_lb.arn
}

output "ssl_listener_arn" {
  description = "ARN of the HTTPS listener"
  value       = aws_lb_listener.app_listener_https.arn
}

output "application_url" {
  description = "The HTTPS URL to access the application"
  value       = "https://${var.domain_name}"
}