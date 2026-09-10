provider "aws" {
  region = "us-east-1"
}

resource "aws_chime_voice_connector" "this" {
  name               = "benchmark-chime-voice-connector"
  require_encryption = true
}

resource "aws_chime_voice_connector_streaming" "this" {
  voice_connector_id             = aws_chime_voice_connector.this.id
  disabled                       = true
  data_retention                 = 5
  streaming_notification_targets = ["SNS"]
}
