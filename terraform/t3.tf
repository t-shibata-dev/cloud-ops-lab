# S3 Bucket for WordPress media
resource "aws_s3_bucket" "media" {
  bucket = "${var.project_name}-media-${var.account_id}"

  tags = {
    Name    = "${var.project_name}-media"
    Project = var.project_name
  }
}

# S3のパブリックアクセスをブロック
resource "aws_s3_bucket_public_access_block" "media" {
  bucket = aws_s3_bucket.media.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# バージョニング有効化
resource "aws_s3_bucket_versioning" "media" {
  bucket = aws_s3_bucket.media.id

  versioning_configuration {
    status = "Enabled"
  }
}
