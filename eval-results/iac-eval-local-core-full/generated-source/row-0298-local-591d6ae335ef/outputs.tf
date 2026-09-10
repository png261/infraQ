output "codebuild_project_name" {
  description = "Name of the CodeBuild autograder project."
  value       = aws_codebuild_project.autograder.name
}

output "results_bucket_name" {
  description = "S3 bucket where CodeBuild stores autograder results."
  value       = aws_s3_bucket.autograder_results.bucket
}

output "isolated_vpc_id" {
  description = "VPC ID for the isolated autograder network."
  value       = aws_vpc.autograder.id
}
