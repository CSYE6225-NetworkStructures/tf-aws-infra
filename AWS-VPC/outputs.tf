output "vpc_id" {
  value = aws_vpc.main.id
}

output "vpc_name" {
  value = local.unique_vpc_name
}

output "aws_region" {
  value = var.aws_region
}

output "availability_zones" {
  value = local.availability_zones
}

output "public_subnet_ids" {
  value = aws_subnet.public_subnets[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private_subnets[*].id
}

output "terraform_state_key" {
  value = "terraform-${var.aws_region}-${replace(var.vpc_cidr, ".", "-")}.tfstate"
}

output "ec2_instance_id" {
  value = aws_instance.web.id
}

output "ec2_public_ip" {
  value = aws_instance.web.public_ip
}

output "application_sg_id" {
  value = aws_security_group.application_sg.id
}
