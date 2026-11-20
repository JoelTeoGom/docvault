resource "aws_dynamodb_table" "files" {
  name         = var.table_name
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
    name = "gsiPK"
    type = "S"
  }

  attribute {
    name = "gsiSK"
    type = "N"
  }

  global_secondary_index {
    name            = "sweep-index"
    hash_key        = "gsiPK"
    range_key       = "gsiSK"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }
}
