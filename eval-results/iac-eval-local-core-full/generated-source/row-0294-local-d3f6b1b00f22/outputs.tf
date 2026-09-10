output "codebuild_project_name" {
  description = "Name of the CodeBuild autograder project."
  value       = aws_codebuild_project.autograder.name
}

output "results_bucket_name" {
  description = "Name of the S3 bucket storing autograder results."
  value       = aws_s3_bucket.autograder_results.bucket
}
