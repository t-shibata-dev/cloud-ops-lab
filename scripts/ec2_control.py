import boto3
import sys

def get_instance_status(instance_id):
    ec2 = boto3.client("ec2")
    response = ec2.describe_instances(InstanceIds=[instance_id])
    state = response["Reservations"][0]["Instances"][0]["State"]["Name"]
    print(f"Status: {instance_id} → {state}")
    return state

def start_instance(instance_id):
    ec2 = boto3.client("ec2")
    state = get_instance_status(instance_id)
    if state == "running":
        print(f"既に起動しています: {instance_id}")
        return
    ec2.start_instances(InstanceIds=[instance_id])
    print(f"起動しました: {instance_id}")

def stop_instance(instance_id):
    ec2 = boto3.client("ec2")
    state = get_instance_status(instance_id)
    if state == "stopped":
        print(f"既に停止しています: {instance_id}")
        return
    ec2.stop_instances(InstanceIds=[instance_id])
    print(f"停止しました: {instance_id}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python ec2_control.py <action> <instance_id>")
        print("  action: status | start | stop")
        sys.exit(1)

    action      = sys.argv[1]
    instance_id = sys.argv[2]

    if action == "status":
        get_instance_status(instance_id)
    elif action == "start":
        start_instance(instance_id)
    elif action == "stop":
        stop_instance(instance_id)
    else:
        print(f"Error: 不明なaction: {action}")
        sys.exit(1)
