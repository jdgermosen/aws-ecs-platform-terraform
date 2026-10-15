output "vault_name" {
  description = "Backup vault name."
  value       = aws_backup_vault.this.name
}

output "plan_id" {
  description = "Backup plan ID."
  value       = aws_backup_plan.this.id
}
