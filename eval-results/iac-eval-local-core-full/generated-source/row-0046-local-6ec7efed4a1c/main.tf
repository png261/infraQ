resource "aws_lex_intent" "book_trip" {
  name        = "BookTrip"
  description = "Collects trip booking details from the user."

  create_version = false

  sample_utterances = [
    "I want to book a trip",
    "Book a trip",
    "Help me arrange travel",
    "Plan travel for me"
  ]

  slot {
    name              = "Destination"
    description       = "Destination city for the trip."
    slot_constraint   = "Required"
    slot_type         = "AMAZON.US_CITY"
    slot_type_version = "$LATEST"
    priority          = 1

    sample_utterances = [
      "I want to go to {Destination}",
      "Book a trip to {Destination}",
      "Travel to {Destination}"
    ]

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content      = "What city would you like to visit?"
        content_type = "PlainText"
      }
    }
  }

  slot {
    name              = "DepartureDate"
    description       = "Date when the user wants to start the trip."
    slot_constraint   = "Required"
    slot_type         = "AMAZON.DATE"
    slot_type_version = "$LATEST"
    priority          = 2

    sample_utterances = [
      "I want to leave on {DepartureDate}",
      "Departing {DepartureDate}",
      "My travel date is {DepartureDate}"
    ]

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content      = "What date would you like to depart?"
        content_type = "PlainText"
      }
    }
  }

  confirmation_prompt {
    max_attempts = 2

    message {
      content      = "Please confirm that you want to book a trip to {Destination} on {DepartureDate}."
      content_type = "PlainText"
    }
  }

  rejection_statement {
    message {
      content      = "Okay, I will not book the trip."
      content_type = "PlainText"
    }
  }

  fulfillment_activity {
    type = "ReturnIntent"
  }

  conclusion_statement {
    message {
      content      = "Thanks. I have collected the information needed to book your trip."
      content_type = "PlainText"
    }
  }

  follow_up_prompt {
    prompt {
      max_attempts = 2

      message {
        content      = "Would you like to book another trip?"
        content_type = "PlainText"
      }
    }

    rejection_statement {
      message {
        content      = "Okay, have a great day."
        content_type = "PlainText"
      }
    }
  }
}

resource "aws_lex_bot" "trip_booking" {
  name        = "TripBookingBot"
  description = "A Lex bot that gathers information to book a trip."

  abort_statement {
    message {
      content      = "Sorry, I could not complete your trip booking request."
      content_type = "PlainText"
    }
  }

  child_directed              = false
  create_version              = false
  detect_sentiment            = false
  enable_model_improvements   = true
  idle_session_ttl_in_seconds = 300
  locale                      = "en-US"
  process_behavior            = "BUILD"
  voice_id                    = "Salli"

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
