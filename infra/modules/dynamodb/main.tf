terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.40" }
  }
}

# Single-table design (per the app's DynamoDB study guide): one partition per
# user (PK = USER#<sub>), one item per entity (SK = SETTINGS | ITEM#id | LOG#... ).
# GSI1 is an overloaded index for alternate access patterns. On-demand billing,
# PITR + deletion protection on, encrypted at rest.
resource "aws_dynamodb_table" "this" {
  name         = var.name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  attribute {
    name = "PK"
    type = "S"
  }
  attribute {
    name = "SK"
    type = "S"
  }
  attribute {
    name = "GSI1PK"
    type = "S"
  }
  attribute {
    name = "GSI1SK"
    type = "S"
  }

  global_secondary_index {
    name            = "GSI1"
    hash_key        = "GSI1PK"
    range_key       = "GSI1SK"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  # A TTL attribute for ephemeral items (e.g. review-scheduling scratch); harmless
  # if unused — items without the attribute never expire.
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  deletion_protection_enabled = var.deletion_protection

  tags = var.tags
}
