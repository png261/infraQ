def handler(event, context):
    return {
        "statusCode": 200,
        "body": "example_lambda invoked",
        "event": event,
    }
