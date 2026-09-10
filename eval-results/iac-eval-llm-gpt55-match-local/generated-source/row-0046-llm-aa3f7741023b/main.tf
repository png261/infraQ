terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_lex_slot_type" "trip_type" {
  name                     = "TripType"
  description              = "The type of trip the user wants to book."
  create_version           = true
  value_selection_strategy = "ORIGINAL_VALUE"

  enumeration_value {
    value    = "flight"
    synonyms = ["airplane", "plane", "air travel"]
  }

  enumeration_value {
    value    = "hotel"
    synonyms = ["room", "lodging", "accommodation"]
  }

  enumeration_value {
    value    = "car"
    synonyms = ["rental car", "vehicle", "auto"]
  }
}

resource "aws_lex_intent" "book_trip" {
  name           = "BookTrip"
  description    = "Intent used to collect information required to book a trip."
  create_version = true

  sample_utterances = [
    "I want to book a trip",
    "Book a trip",
    "Help me plan travel",
    "I need to book travel",
    "Reserve a trip for me",
    "I want to book a {TripType}",
    "Book a {TripType} from {DepartureCity} to {DestinationCity}",
    "I need a {TripType} on {DepartureDate}"
  ]

  slot {
    name                  = "TripType"
    description           = "The type of trip the user wants to book."
    priority              = 1
    slot_constraint       = "Required"
    slot_type             = aws_lex_slot_type.trip_type.name
    slot_type_version     = aws_lex_slot_type.trip_type.version
    sample_utterances     = []
    response_card         = null

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content_type = "PlainText"
        content      = "What type of trip would you like to book: flight, hotel, or car?"
      }
    }
  }

  slot {
    name                  = "DepartureCity"
    description           = "The city where the trip starts."
    priority              = 2
    slot_constraint       = "Required"
    slot_type             = "AMAZON.US_CITY"
    slot_type_version     = null
    sample_utterances     = []
    response_card         = null

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content_type = "PlainText"
        content      = "What city are you departing from?"
      }
    }
  }

  slot {
    name                  = "DestinationCity"
    description           = "The destination city for the trip."
    priority              = 3
    slot_constraint       = "Required"
    slot_type             = "AMAZON.US_CITY"
    slot_type_version     = null
    sample_utterances     = []
    response_card         = null

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content_type = "PlainText"
        content      = "What city are you traveling to?"
      }
    }
  }

  slot {
    name                  = "DepartureDate"
    description           = "The date the user wants to start the trip."
    priority              = 4
    slot_constraint       = "Required"
    slot_type             = "AMAZON.DATE"
    slot_type_version     = null
    sample_utterances     = []
    response_card         = null

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content_type = "PlainText"
        content      = "What date would you like to depart?"
      }
    }
  }

  slot {
    name                  = "ReturnDate"
    description           = "The return date for the trip."
    priority              = 5
    slot_constraint       = "Optional"
    slot_type             = "AMAZON.DATE"
    slot_type_version     = null
    sample_utterances     = []
    response_card         = null

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content_type = "PlainText"
        content      = "What date would you like to return? You can say skip if it is a one-way trip."
      }
    }
  }

  confirmation_prompt {
    max_attempts = 2

    message {
      content_type = "PlainText"
      content      = "Please confirm: you want to book a {TripType} from {DepartureCity} to {DestinationCity} departing on {DepartureDate}. Is that correct?"
    }
  }

  rejection_statement {
    message {
      content_type = "PlainText"
      content      = "Okay, I will not book the trip."
    }
  }

  conclusion_statement {
    message {
      content_type = "PlainText"
      content      = "Thanks. I have collected your trip details and will proceed with the booking request."
    }
  }

  fulfillment_activity {
    type = "ReturnIntent"
  }
}

resource "aws_lex_bot" "trip_booking_bot" {
  name                        = "TripBookingBot"
  description                 = "A Lex bot that collects information needed to book a trip."
  locale                      = "en-US"
  child_directed              = false
  idle_session_ttl_in_seconds = 300
  voice_id                    = "Joanna"
  process_behavior            = "BUILD"
  detect_sentiment            = false
  enable_model_improvements   = true
  create_version              = true

  clarification_prompt {
    max_attempts = 2

    message {
      content_type = "PlainText"
      content      = "Sorry, I did not understand that. You can say something like, book a trip."
    }
  }

  abort_statement {
    message {
      content_type = "PlainText"
      content      = "Sorry, I am unable to help with that trip booking request right now."
    }
  }

  intent {
    intent_name    = aws_lex_intent.book_trip.name
    intent_version = aws_lex_intent.book_trip.version
  }

  depends_on = [
    aws_lex_intent.book_trip
  ]
}