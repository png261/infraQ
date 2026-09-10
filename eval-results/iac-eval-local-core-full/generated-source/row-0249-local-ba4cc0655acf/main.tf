resource "aws_chime_voice_connector" "primary" {
  name               = "iac-eval-primary-voice-connector"
  require_encryption = true
}

resource "aws_chime_voice_connector" "secondary" {
  name               = "iac-eval-secondary-voice-connector"
  require_encryption = true
}

resource "aws_chime_voice_connector_group" "this" {
  name = "iac-eval-voice-connector-group"

  connector {
    voice_connector_id = aws_chime_voice_connector.primary.id
    priority           = 1
  }

  connector {
    voice_connector_id = aws_chime_voice_connector.secondary.id
    priority           = 2
  }
}
