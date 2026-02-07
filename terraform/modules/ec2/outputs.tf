output "instance_id" {
  description = "Windows EC2 instance ID"
  value       = aws_instance.windows.id
}

output "instance_private_ip" {
  description = "Private IP address of Windows EC2"
  value       = aws_instance.windows.private_ip
}

output "security_group_id" {
  description = "Security group ID for Windows EC2"
  value       = aws_security_group.windows.id
}

output "iam_role_arn" {
  description = "IAM role ARN for Windows EC2"
  value       = aws_iam_role.windows_ssm.arn
}

output "ssm_connect_command" {
  description = "AWS CLI command to connect to Windows EC2 via SSM"
  value       = "aws ssm start-session --target ${aws_instance.windows.id}"
}
