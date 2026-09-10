def lambda_handler(event, context):
    """Entry point for the daily EventBridge schedule."""
    print("Daily 07:00 UTC scheduled Lambda invocation received.")
    return {"statusCode": 200, "body": "ok"}
