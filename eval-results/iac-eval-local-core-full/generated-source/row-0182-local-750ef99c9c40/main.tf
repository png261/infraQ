provider "aws" {
  region = "us-east-1"
}

resource "aws_sagemaker_human_task_ui" "test" {
  human_task_ui_name = "test-human-task-ui"

  ui_template {
    content = file("${path.module}/sagemaker-human-task-ui-template.html")
  }
}
