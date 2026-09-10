data "aws_iam_policy_document" "eb_ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eb_ec2_role" {
  name               = "eb_ec2_role"
  assume_role_policy = data.aws_iam_policy_document.eb_ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "eb_web_tier" {
  role       = aws_iam_role.eb_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
}

resource "aws_iam_instance_profile" "eb_ec2_profile" {
  name = "eb_ec2_profile"
  role = aws_iam_role.eb_ec2_role.name
}

resource "aws_elastic_beanstalk_application" "batch_job_app" {
  name = "batch_job_app"
}

resource "aws_s3_bucket" "sampleapril26426" {
  bucket = "sampleapril26426"
}

resource "aws_s3_object" "examplebucket_object" {
  bucket = aws_s3_bucket.sampleapril26426.bucket
  key    = "examplebucket_object"
  source = "${path.module}/worker_source_bundle.zip"
}

resource "aws_elastic_beanstalk_application_version" "version" {
  name        = "version"
  application = aws_elastic_beanstalk_application.batch_job_app.name
  bucket      = aws_s3_object.examplebucket_object.bucket
  key         = aws_s3_object.examplebucket_object.key
}

resource "aws_sqs_queue" "batch_job_queue" {
  name = "batch_job_queue"
}

resource "aws_elastic_beanstalk_environment" "worker" {
  name                = "batch-job-worker-env"
  application         = aws_elastic_beanstalk_application.batch_job_app.name
  solution_stack_name = "64bit Amazon Linux 2 v3.6.5 running Docker"
  tier                = "Worker"
  version_label       = aws_elastic_beanstalk_application_version.version.name

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "EnvironmentType"
    value     = "SingleInstance"
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.eb_ec2_profile.name
  }

  setting {
    namespace = "aws:elasticbeanstalk:sqsd"
    name      = "WorkerQueueURL"
    value     = aws_sqs_queue.batch_job_queue.url
  }

  setting {
    namespace = "aws:elasticbeanstalk:sqsd"
    name      = "HttpPath"
    value     = "/"
  }

  setting {
    namespace = "aws:elasticbeanstalk:sqsd"
    name      = "MimeType"
    value     = "application/json"
  }
}
