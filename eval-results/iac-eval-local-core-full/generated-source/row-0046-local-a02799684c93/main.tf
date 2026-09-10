resource "aws_lex_intent" "book_trip" {
  name        = "BookTrip"
  description = "Collects trip booking details from a traveler."

  sample_utterances = [
    "Book a trip",
    "I want to book a trip",
    "Plan travel from New York to Seattle",
    "Book travel for me"
  ]

  fulfillment_activity {
    type = "ReturnIntent"
  }

  rejection_statement {
    message {
      content      = "Okay, I will not book the trip."
      content_type = "PlainText"
    }
  }

  slot {
    name              = "DestinationCity"
    description       = "The destination city for the trip."
    priority          = 1
    slot_constraint   = "Required"
    slot_type         = "AMAZON.US_CITY"
    value_elicitation_prompt {
      max_attempts = 2
      message {
        content      = "What city are you traveling to?"
        content_type = "PlainText"
      }
    }
  }

  slot {
    name              = "DepartureCity"
    description       = "The departure city for the trip."
    priority          = 2
    slot_constraint   = "Required"
    slot_type         = "AMAZON.US_CITY"
    value_elicitation_prompt {
      max_attempts = 2
      message {
        content      = "What city are you leaving from?"
        content_type = "PlainText"
      }
    }
  }

  slot {
    name              = "TravelDate"
    description       = "The date when the traveler wants to begin the trip."
    priority          = 3
    slot_constraint   = "Required"
    slot_type         = "AMAZON.DATE"
    value_elicitation_prompt {
      max_attempts = 2
      message {
        content      = "What date would you like to travel?"
        content_type = "PlainText"
      }
    }
  }
}

resource "aws_lex_bot" "book_trip" {
  name                        = "BookTripBot"
  child_directed              = false
  create_version              = false
  description                 = "A Lex bot that helps customers book a trip."
  detect_sentiment            = false
  enable_model_improvements   = true
  idle_session_ttl_in_seconds = 300
  locale                      = "en-US"
  process_behavior            = "BUILD"
  voice_id                    = "Salli"

  abort_statement {
    message {
      content      = "Sorry, I could not complete your trip booking request."
      content_type = "PlainText"
    }
  }

  clarification_prompt {
    max_attempts = 2
    message {
      content      = "I did not understand. You can say, book a trip."
      content_type = "PlainText"
    }
  }

  intent {
    intent_name    = aws_lex_intent.book_trip.name
    intent_version = "$LATEST"
  }
}
