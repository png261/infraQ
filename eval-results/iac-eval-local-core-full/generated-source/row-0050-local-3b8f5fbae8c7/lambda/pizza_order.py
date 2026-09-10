def handler(event, context):
    """Minimal Lex V1 fulfillment hook for pizza orders."""
    intent_name = event.get("currentIntent", {}).get("name", "OrderPizza")

    return {
        "sessionAttributes": event.get("sessionAttributes", {}),
        "dialogAction": {
            "type": "Close",
            "fulfillmentState": "Fulfilled",
            "message": {
                "contentType": "PlainText",
                "content": f"Thanks, your pizza order was received by {intent_name}."
            }
        }
    }
