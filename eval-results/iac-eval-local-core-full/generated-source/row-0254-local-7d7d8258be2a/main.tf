resource "aws_chime_voice_connector" "this" {
  name               = "iac-eval-voice-connector"
  require_encryption = true
}

resource "aws_chime_voice_connector_streaming" "this" {
  voice_connector_id = aws_chime_voice_connector.this.id
  data_retention     = 7
}
