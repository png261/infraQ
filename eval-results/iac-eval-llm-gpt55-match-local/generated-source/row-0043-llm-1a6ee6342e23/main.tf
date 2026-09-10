terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the Lex bot will be created."
  type        = string
  default     = "us-east-1"
}

variable "bot_name" {
  description = "Name of the Amazon Lex V2 bot."
  type        = string
  default     = "hotel-booking-bot"
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "lex_bot_role" {
  name = "${var.bot_name}-lex-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lexv2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "lex_bot_policy" {
  name = "${var.bot_name}-lex-policy"
  role = aws_iam_role.lex_bot_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "polly:SynthesizeSpeech",
          "comprehend:DetectSentiment"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lexv2models_bot" "hotel_booking_bot" {
  name                        = var.bot_name
  description                 = "Amazon Lex V2 bot for booking hotel rooms with multiple slots."
  role_arn                    = aws_iam_role.lex_bot_role.arn
  idle_session_ttl_in_seconds = 300

  data_privacy {
    child_directed = false
  }
}

resource "aws_lexv2models_bot_locale" "en_us" {
  bot_id                           = aws_lexv2models_bot.hotel_booking_bot.id
  bot_version                      = "DRAFT"
  locale_id                        = "en_US"
  description                      = "English US locale for the hotel booking bot."
  n_lu_intent_confidence_threshold = 0.40

  voice_settings {
    voice_id = "Joanna"
  }
}

resource "aws_lexv2models_slot_type" "room_type" {
  bot_id      = aws_lexv2models_bot.hotel_booking_bot.id
  bot_version = "DRAFT"
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id

  name        = "RoomType"
  description = "Available hotel room types."

  value_selection_setting {
    resolution_strategy = "ORIGINAL_VALUE"
  }

  slot_type_values {
    sample_value {
      value = "single"
    }

    synonyms {
      value = "one bed"
    }

    synonyms {
      value = "standard"
    }
  }

  slot_type_values {
    sample_value {
      value = "double"
    }

    synonyms {
      value = "two beds"
    }

    synonyms {
      value = "double bed"
    }
  }

  slot_type_values {
    sample_value {
      value = "suite"
    }

    synonyms {
      value = "luxury room"
    }

    synonyms {
      value = "premium suite"
    }
  }

  depends_on = [
    aws_lexv2models_bot_locale.en_us
  ]
}

resource "aws_lexv2models_intent" "book_hotel" {
  bot_id      = aws_lexv2models_bot.hotel_booking_bot.id
  bot_version = "DRAFT"
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id

  name        = "BookHotel"
  description = "Intent for booking a hotel room."

  sample_utterance {
    utterance = "Book a hotel room"
  }

  sample_utterance {
    utterance = "I want to reserve a room"
  }

  sample_utterance {
    utterance = "Book a {RoomType} room"
  }

  sample_utterance {
    utterance = "I need a {RoomType} room on {CheckInDate}"
  }

  sample_utterance {
    utterance = "Reserve a {RoomType} room for {NumberOfNights} nights"
  }

  closing_setting {
    closing_response {
      message_group {
        message {
          plain_text_message {
            value = "Your hotel room reservation request has been captured."
          }
        }
      }
    }
  }

  depends_on = [
    aws_lexv2models_bot_locale.en_us
  ]
}

resource "aws_lexv2models_slot" "check_in_date" {
  bot_id      = aws_lexv2models_bot.hotel_booking_bot.id
  bot_version = "DRAFT"
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id
  intent_id   = aws_lexv2models_intent.book_hotel.intent_id

  name        = "CheckInDate"
  description = "The date the guest wants to check in."
  slot_type_id = "AMAZON.Date"

  value_elicitation_setting {
    slot_constraint = "Required"

    prompt_specification {
      max_retries = 2

      message_group {
        message {
          plain_text_message {
            value = "What date would you like to check in?"
          }
        }
      }
    }
  }
}

resource "aws_lexv2models_slot" "number_of_nights" {
  bot_id      = aws_lexv2models_bot.hotel_booking_bot.id
  bot_version = "DRAFT"
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id
  intent_id   = aws_lexv2models_intent.book_hotel.intent_id

  name        = "NumberOfNights"
  description = "The number of nights for the hotel stay."
  slot_type_id = "AMAZON.Number"

  value_elicitation_setting {
    slot_constraint = "Required"

    prompt_specification {
      max_retries = 2

      message_group {
        message {
          plain_text_message {
            value = "How many nights will you be staying?"
          }
        }
      }
    }
  }
}

resource "aws_lexv2models_slot" "room_type" {
  bot_id      = aws_lexv2models_bot.hotel_booking_bot.id
  bot_version = "DRAFT"
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id
  intent_id   = aws_lexv2models_intent.book_hotel.intent_id

  name        = "RoomType"
  description = "The type of room the guest wants to book."
  slot_type_id = aws_lexv2models_slot_type.room_type.slot_type_id

  value_elicitation_setting {
    slot_constraint = "Required"

    prompt_specification {
      max_retries = 2

      message_group {
        message {
          plain_text_message {
            value = "What type of room would you like: single, double, or suite?"
          }
        }
      }
    }
  }
}

resource "aws_lexv2models_slot" "guest_name" {
  bot_id      = aws_lexv2models_bot.hotel_booking_bot.id
  bot_version = "DRAFT"
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id
  intent_id   = aws_lexv2models_intent.book_hotel.intent_id

  name        = "GuestName"
  description = "The name of the guest for the reservation."
  slot_type_id = "AMAZON.Person"

  value_elicitation_setting {
    slot_constraint = "Required"

    prompt_specification {
      max_retries = 2

      message_group {
        message {
          plain_text_message {
            value = "What name should I use for the reservation?"
          }
        }
      }
    }
  }
}

resource "aws_lexv2models_intent" "fallback" {
  bot_id      = aws_lexv2models_bot.hotel_booking_bot.id
  bot_version = "DRAFT"
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id

  name                    = "FallbackIntent"
  parent_intent_signature = "AMAZON.FallbackIntent"
  description             = "Default fallback intent."

  depends_on = [
    aws_lexv2models_bot_locale.en_us
  ]
}

resource "aws_lexv2models_bot_version" "version_1" {
  bot_id      = aws_lexv2models_bot.hotel_booking_bot.id
  description = "Version 1 of the hotel booking bot."

  locale_specification {
    locale_id = aws_lexv2models_bot_locale.en_us.locale_id

    bot_version_locale_details {
      source_bot_version = "DRAFT"
    }
  }

  depends_on = [
    aws_lexv2models_slot.check_in_date,
    aws_lexv2models_slot.number_of_nights,
    aws_lexv2models_slot.room_type,
    aws_lexv2models_slot.guest_name,
    aws_lexv2models_intent.fallback
  ]
}

resource "aws_lexv2models_bot_alias" "production" {
  bot_alias_name = "production"
  bot_id         = aws_lexv2models_bot.hotel_booking_bot.id
  bot_version    = aws_lexv2models_bot_version.version_1.bot_version
  description    = "Production alias for the hotel booking bot."

  bot_alias_locale_settings {
    locale_id = aws_lexv2models_bot_locale.en_us.locale_id

    bot_alias_locale_setting {
      enabled = true
    }
  }

  sentiment_analysis_settings {
    detect_sentiment = true
  }
}

output "lex_bot_id" {
  description = "The ID of the Amazon Lex V2 bot."
  value       = aws_lexv2models_bot.hotel_booking_bot.id
}

output "lex_bot_alias_id" {
  description = "The ID of the Amazon Lex V2 bot alias."
  value       = aws_lexv2models_bot_alias.production.bot_alias_id
}

output "lex_bot_version" {
  description = "The published Lex bot version."
  value       = aws_lexv2models_bot_version.version_1.bot_version
}