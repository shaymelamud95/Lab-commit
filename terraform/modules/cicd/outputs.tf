output "codecommit_repository_url" {
  description = "CodeCommit repository clone URL (HTTPS)"
  value       = aws_codecommit_repository.app.clone_url_http
}

output "codecommit_repository_ssh" {
  description = "CodeCommit repository clone URL (SSH)"
  value       = aws_codecommit_repository.app.clone_url_ssh
}

output "codepipeline_name" {
  description = "CodePipeline name"
  value       = aws_codepipeline.app.name
}

output "codepipeline_url" {
  description = "CodePipeline console URL"
  value       = "https://console.aws.amazon.com/codesuite/codepipeline/pipelines/${aws_codepipeline.app.name}/view?region=${var.aws_region}"
}
