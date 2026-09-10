def handler(event, context):
    print("Daily EventBridge invocation received", event)
    return {"statusCode": 200, "body": "ok"}
