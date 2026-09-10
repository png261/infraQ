output "codebuild_output_bucket_name" {
  description = "Name of the S3 bucket used for CodeBuild artifacts."
  value       = aws_s3_bucket.codebuild_output.bucket
}

output "codebuild_project_name" {
  description = "Name of the CodeBuild project."
  value       = aws_codebuild_project.student_output.name
}
