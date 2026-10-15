output "instance_id" {
  description = "Ops host instance ID (connect with `aws ssm start-session --target <id>`)."
  value       = aws_instance.this.id
}

output "ansible_transfer_bucket" {
  description = "S3 bucket for Ansible's SSM connection plugin."
  value       = aws_s3_bucket.ansible_transfer.bucket
}
