def lambda_handler(event, context):
    print("EC2 image created event received:", event)
    return {"statusCode": 200, "body": "ok"}
