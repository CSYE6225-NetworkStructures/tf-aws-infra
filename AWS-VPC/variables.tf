variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI profile to use (optional)"
  type        = string
  default     = "ass5"
}

variable "aws_access_key" {
  description = "AWS access key (used if profile is not specified)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS secret key (used if profile is not specified)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_count" {
  description = "Number of subnets to create (both public and private)"
  type        = number
  default     = 3
}

variable "app_port" {
  description = "Port for the application"
  type        = number
  default     = 8080
}

variable "ami_id" {
  description = "AMI ID for EC2 instance"
  type        = string
  default     = "ami-0b5f68157ae21151d"
}

variable "key_name" {
  description = "Name of the SSH key pair to use for EC2 instance"
  type        = string
  default     = "packer_ec2"
}

variable "db_engine" {
  description = "Database engine (mysql, mariadb, or postgres)"
  type        = string
  default     = "mysql"
}

variable "db_engine_version" {
  description = "Version of the database engine"
  type        = string
  default     = "8.0"
}

variable "db_parameter_group_family" {
  description = "The family of the DB parameter group"
  type        = string
  default     = "mysql8.0"
}

variable "db_instance_class" {
  description = "Instance class for the RDS instance"
  type        = string
  default     = "db.t3.micro"
}

variable "db_port" {
  description = "Port for the database (3306 for MySQL/MariaDB, 5432 for PostgreSQL)"
  type        = number
  default     = 3306
}

# Removed the db_password variable as we generate it dynamically now

variable "user_data_script_path" {
  description = "Path to the user data script file"
  type        = string
  default     = "setup.sh"
}

variable "route53_zone_id" {
  description = "The Zone ID of the Route53 Hosted Zone for your domain"
  type        = string
  default     = "Z037132013FXVD5YC8420"
}

variable "domain_name" {
  description = "The domain name to use for the application (e.g., dev.example.com or demo.example.com)"
  type        = string
  default     = "demo.mayukhsinha.com"
}

variable "ssh_allowed_cidrs" {
  description = "List of CIDR blocks allowed to SSH to EC2 instances"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Consider restricting this to specific IPs for security
}