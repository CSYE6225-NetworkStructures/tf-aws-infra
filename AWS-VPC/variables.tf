variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI profile to use (if available)"
  type        = string
  default     = ""
}

variable "aws_access_key" {
  description = "AWS access key (fallback if profile is not available)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS secret key (fallback if profile is not available)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.10.0.0/16"
}

variable "subnet_count" {
  description = "Number of subnets (1 public & 1 private per AZ)"
  type        = number
  default     = 3
}

variable "ami_id" {
  description = "Custom AMI ID for EC2"
  type        = string
}

variable "key_name" {
  description = "SSH key pair name for EC2"
  type        = string
}

variable "app_port" {
  description = "Port number on which the application runs"
  type        = number
  default     = 8080
}

