output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "VPC CIDR block."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs, one per AZ."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs, one per AZ."
  value       = aws_subnet.private[*].id
}

output "availability_zones" {
  description = "Availability Zones in use."
  value       = local.azs
}

output "nat_instance_id" {
  description = "NAT instance ID when nat_mode = \"instance\"."
  value       = one(aws_instance.nat[*].id)
}
