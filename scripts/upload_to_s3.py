import boto3
import sys
import os

def upload_file(file_path, bucket_name, s3_key=None):
    """
    ローカルファイルをS3にアップロードする
    
    Args:
        file_path: アップロードするファイルのパス
        bucket_name: S3バケット名
        s3_key: S3上のファイル名（省略時はファイル名をそのまま使用）
    """
    if not os.path.exists(file_path):
        print(f"Error: ファイルが見つかりません: {file_path}")
        sys.exit(1)

    if s3_key is None:
        s3_key = os.path.basename(file_path)

    s3 = boto3.client("s3")

    try:
        s3.upload_file(file_path, bucket_name, s3_key)
        print(f"Success: {file_path} → s3://{bucket_name}/{s3_key}")
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python upload_to_s3.py <file_path> <bucket_name>")
        sys.exit(1)

    file_path   = sys.argv[1]
    bucket_name = sys.argv[2]
    s3_key      = sys.argv[3] if len(sys.argv) > 3 else None

    upload_file(file_path, bucket_name, s3_key)
