import json
import os
import random

import boto3

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")


def lambda_handler(event, context):
    bucket_name = os.environ["BUCKET_NAME"]
    table_name = os.environ["TABLE_NAME"]
    table = dynamodb.Table(table_name)

    response = table.scan(ProjectionExpression="picture_id, s3_key")
    items = response.get("Items", [])
    if not items:
        return {
            "statusCode": 404,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"message": "No cat pictures available"}),
        }

    item = random.choice(items)
    url = s3.generate_presigned_url(
        "get_object",
        Params={"Bucket": bucket_name, "Key": item["s3_key"]},
        ExpiresIn=300,
    )

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"picture_id": item["picture_id"], "url": url}),
    }
