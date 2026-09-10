resource "aws_chime_voice_connector" "this" {
  name               = "iac-eval-voice-connector"
  require_encryption = true
}

resource "aws_chime_voice_connector_logging" "this" {
  voice_connector_id       = aws_chime_voice_connector.this.id
  enable_media_metric_logs = true
}
