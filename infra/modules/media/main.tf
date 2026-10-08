terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.40" }
  }
}

# Private object store for user media (garment photos). The browser never gets
# bucket credentials: the API hands out short-lived presigned POST forms
# (upload, with type + size limits baked into the signed policy) and presigned
# GET URLs (download). Every key lives under users/<sub>/, and the Lambda role
# can only touch that prefix (see modules/lambda).
resource "aws_s3_bucket" "media" {
  bucket = var.bucket_name
  tags   = var.tags
}

resource "aws_s3_bucket_public_access_block" "media" {
  bucket                  = aws_s3_bucket.media.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "media" {
  bucket = aws_s3_bucket.media.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "media" {
  bucket = aws_s3_bucket.media.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Versioning gives a recovery window for accidental deletes/overwrites; the
# lifecycle rule below keeps that window bounded so storage doesn't creep.
resource "aws_s3_bucket_versioning" "media" {
  bucket = aws_s3_bucket.media.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_days
    }
    # Clean up delete markers once no older versions remain behind them.
    expiration {
      expired_object_delete_marker = true
    }
  }

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  depends_on = [aws_s3_bucket_versioning.media]
}

# Browsers upload straight to S3 (presigned POST) and render photos from
# presigned GET URLs, so the app's origins need CORS on the bucket itself.
resource "aws_s3_bucket_cors_configuration" "media" {
  count  = var.enable_cors ? 1 : 0
  bucket = aws_s3_bucket.media.id
  cors_rule {
    allowed_methods = ["GET", "HEAD", "POST"]
    allowed_origins = var.cors_allow_origins
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}

# TLS only — reject any request that isn't over HTTPS.
data "aws_iam_policy_document" "media" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.media.arn, "${aws_s3_bucket.media.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "media" {
  bucket     = aws_s3_bucket.media.id
  policy     = data.aws_iam_policy_document.media.json
  depends_on = [aws_s3_bucket_public_access_block.media]
}
