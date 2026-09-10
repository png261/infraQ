resource "aws_lex_intent" "book_trip" {
  name = "BookTripIntent"

  description = "Collects destination and travel date details for a trip booking request."

  sample_utterances = [
    "Book a trip",
    "I want to travel",
    "Plan my trip",
  ]

  fulfillment_activity {
    type = "ReturnIntent"
  }

  slot {
    name              = "Destination"
    description       = "The city where the user wants to travel."
    slot_constraint   = "Required"
    slot_type         = "AMAZON.City"
    value_elicitation_prompt {
      max_attempts = 2

      message {
        content      = "What city would you like to visit?"
        content_type = "PlainText"
      }
    }
  }

  slot {
    name              = "TravelDate"
    description       = "The date when the user wants to travel."
    slot_constraint   = "Required"
    slot_type         = "AMAZON.DATE"
    value_elicitation_prompt {
      max_attempts = 2

      message {
        content      = "When would you like to travel?"
        content_type = "PlainText"
      }
    }
  }
}

resource "aws_lex_bot" "travel_bot" {
  name        = "TravelBookingBot"
  description = "A minimal Lex bot that gathers travel booking details."

  child_directed = false
  locale         = "en-US"

  abort_statement {
    message {
      content      = "Sorry, I could not complete your travel booking request."
      content_type = "PlainText"
    }
  }

  clarification_prompt {
    max_attempts = 2

    message {
      content      = "I did not understand. You can say book a trip."
      content_type = "PlainText"
    }
  }

  intent {
    intent_name    = aws_lex_intent.book_trip.name
    intent_version = aws_lex_intent.book_trip.version
  }
}
