def handler(event, context):
    """Minimal scheduled Lambda handler."""
    print("Lambda invoked by EventBridge schedule")
    return {"statusCode": 200, "body": "ok"}
