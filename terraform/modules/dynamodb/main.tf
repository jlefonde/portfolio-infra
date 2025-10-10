resource "aws_dynamodb_table" "tables" {
  name      = var.table_name
  hash_key  = var.table_config.hash_key
  range_key = var.table_config.range_key

  billing_mode   = var.table_config.billing_mode
  read_capacity  = var.table_config.read_capacity
  write_capacity = var.table_config.write_capacity

  dynamic "attribute" {
    for_each = var.table_config.attributes

    content {
      name = attribute.value.name
      type = attribute.value.type
    }
  }

  dynamic "global_secondary_index" {
    for_each = var.table_config.global_secondary_indexes != null ? var.table_config.global_secondary_indexes : []

    content {
      name            = global_secondary_index.value.name
      hash_key        = global_secondary_index.value.hash_key
      range_key       = global_secondary_index.value.range_key
      projection_type = global_secondary_index.value.projection_type
    }
  }
}
