import json
import os
import urllib.request
import urllib.error

from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

# boto3・urllib を自動でトレース対象にする
patch_all()

def lambda_handler(event, context):
    url = os.environ["TARGET_URL"]
    sns_topic_arn = os.environ["SNS_TOPIC_ARN"]
    timeout = int(os.environ.get("TIMEOUT_SECONDS", "10"))

    import boto3
    sns = boto3.client("sns")

    try:
        req = urllib.request.Request(url, headers={"User-Agent": "SiteMonitor/1.0"})
        with urllib.request.urlopen(req, timeout=timeout) as response:
            status_code = response.status
            if status_code == 200:
                print(f"OK: {url} returned {status_code}")
                return {"status": "ok", "code": status_code}
            else:
                raise Exception(f"Unexpected status code: {status_code}")

    except Exception as e:
        message = f"[ALERT] Site down: {url}\nError: {str(e)}"
        print(message)
        sns.publish(
            TopicArn=sns_topic_arn,
            Subject="[SiteMonitor] Site Down Alert",
            Message=message,
        )
        return {"status": "alert_sent", "error": str(e)}
