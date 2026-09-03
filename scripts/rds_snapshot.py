import boto3
import sys
from datetime import datetime

def take_snapshot(db_identifier):
    rds = boto3.client("rds")
    
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    snapshot_id = f"{db_identifier}-snapshot-{timestamp}"

    try:
        response = rds.create_db_snapshot(
            DBSnapshotIdentifier=snapshot_id,
            DBInstanceIdentifier=db_identifier
        )
        snapshot = response["DBSnapshot"]
        print(f"Success: スナップショット作成開始")
        print(f"  ID     : {snapshot['DBSnapshotIdentifier']}")
        print(f"  Status : {snapshot['Status']}")
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

def list_snapshots(db_identifier):
    rds = boto3.client("rds")
    
    response = rds.describe_db_snapshots(
        DBInstanceIdentifier=db_identifier,
        SnapshotType="manual"
    )
    snapshots = response["DBSnapshots"]
    
    if not snapshots:
        print("スナップショットはありません")
        return

    print(f"スナップショット一覧: {db_identifier}")
    for s in snapshots:
        print(f"  {s['DBSnapshotIdentifier']} | {s['Status']} | {s['SnapshotCreateTime'].strftime('%Y-%m-%d %H:%M:%S')}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python rds_snapshot.py <action> <db_identifier>")
        print("  action: create | list")
        sys.exit(1)

    action        = sys.argv[1]
    db_identifier = sys.argv[2]

    if action == "create":
        take_snapshot(db_identifier)
    elif action == "list":
        list_snapshots(db_identifier)
    else:
        print(f"Error: 不明なaction: {action}")
        sys.exit(1)
