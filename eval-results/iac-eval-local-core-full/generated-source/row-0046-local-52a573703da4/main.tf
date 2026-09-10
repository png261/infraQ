resource "aws_lex_intent" "book_trip" {
  name        = "BookTrip"
  description = "Collects trip booking details such as destination, travel date, and traveler count."

  sample_utterances = [
    "Book a trip",
    "I want to book travel",
    "Plan a vacation",
    "Help me book a trip to {Destination}",
    "Book travel to {Destination} on {TravelDate}"
  ]

  slot {
    name              = "Destination"
    description       = "Destination city for the trip."
    slot_constraint   = "Required"
    slot_type         = "AMAZON.US_CITY"
    slot_type_version = "$LATEST"
    value_elicitation_prompt {
      max_attempts = 2
      messages {
        content      = "Where would you like to travel?"
        content_type = "PlainText"
      }
    }
    priority = 1
    sample_utterances = [
      "to {Destination}",
      "I am going to {Destination}"
    ]
  }

  slot {
    name              = "TravelDate"
    description       = "Date when the traveler wants to depart."
    slot_constraint   = "Required"
    slot_type         = "AMAZON.DATE"
    slot_type_version = "$LATEST"
    value_elicitation_prompt {
      max_attempts = 2
      messages {
        content      = "What date would you like to travel?"
        content_type = "PlainText"
      }
    }
    priority = 2
    sample_utterances = [
      "on {TravelDate}",
      "leaving {TravelDate}"
    ]
  }

  slot {
    name              = "TravelerCount"
    description       = "Number of travelers for the booking."
    slot_constraint   = "Required"
    slot_type         = "AMAZON.NUMBER"
    slot_type_version = "$LATEST"
    value_elicitation_prompt {
      max_attempts = 2
      messages {
        content      = "How many travelers are going?"
        content_type = "PlainText"
      }
    }
    priority = 3
    sample_utterances = [
      "for {TravelerCount} people",
      "{TravelerCount} travelers"
    ]
  }

  confirmation_prompt {
    max_attempts = 2
    messages {
      content      = "Please confirm that you want to book a trip to {Destination} on {TravelDate} for {TravelerCount} travelers."
      content_type = "PlainText"
    }
  }

  rejection_statement {
    messages {
      content      = "Okay, I will not book this trip."
      content_type = "PlainText"
    }
  }

  fulfillment_activity {
    type = "ReturnIntent"
  }

  conclusion_statement {
    messages {
      content      = "Thanks. I have the information needed to book your trip."
      content_type = "PlainText"
    }
  }

  create_version = false
}

resource "aws_lex_bot" "trip_booking" {
  name                            = "TripBookingBot"
  description                     = "Amazon Lex bot for booking a trip."
  child_directed                  = false
  create_version                  = false
  detect_sentiment                = false
  enable_model_improvements       = true
  idle_session_ttl_in_seconds     = 300
  locale                          = "en-US"
  nlu_intent_confidence_threshold = 0.4
  process_behavior                = "BUILD"
  voice_id                        = "Joanna"

  abort_statement {
    messages {
      content      = "Sorry, I could not complete the trip booking request."
      content_type = "PlainText"
    }
  }

  clarification_prompt {
    max_attempts = 2
    messages {
      content      = "I can help book a trip. For example, say book a trip to Seattle tomorrow."
      content_type = "PlainText"
    }
  }

  intent {
    intent_name    = aws_lex_intent.book_trip.name
    intent_version = "$LATEST"
  }

  depends_on = [aws_lex_intent.book_trip]
}
