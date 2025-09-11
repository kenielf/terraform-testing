resource "aws_dynamodb_table" "dynamodb_tables" {
  for_each = local.dynamodb_tables

  name         = "${var.client}-${each.key}"
  billing_mode = each.value.billing
  hash_key     = each.value.hash.name
  range_key    = each.value.range.enabled ? each.value.range.name : null

  # Provisioned Attributes
  read_capacity  = each.value.billing == "PROVISIONED" ? each.value.capacity.read : null
  write_capacity = each.value.billing == "PROVISIONED" ? each.value.capacity.write : null

  dynamic "attribute" {
    for_each = distinct(concat(
      [{ name = each.value.hash.name, type = each.value.hash.type }],
      each.value.range.enabled ? [{ name = each.value.range.name, type = each.value.range.type }] : [],
      [for idx_name, idx in(each.value.secondary_indexes != null ? each.value.secondary_indexes : {}) : { name = idx_name, type = idx.type }],
      [for _, idx in(each.value.secondary_indexes != null ? each.value.secondary_indexes : {}) : { name = idx.range.name, type = idx.range.type } if idx.range.enabled],
    ))
    content {
      name = attribute.value.name
      type = attribute.value.type
    }
  }

  dynamic "on_demand_throughput" {
    for_each = each.value.billing == "PAY_PER_REQUEST" ? { this = true } : {}
    content {
      max_read_request_units  = each.value.capacity.read
      max_write_request_units = each.value.capacity.write
    }
  }

  dynamic "global_secondary_index" {
    for_each = each.value.secondary_indexes
    content {
      name            = global_secondary_index.key
      hash_key        = global_secondary_index.key
      range_key       = global_secondary_index.value.range.enabled ? global_secondary_index.name : null
      read_capacity   = each.value.billing == "PROVISIONED" ? each.value.capacity.read : null
      write_capacity  = each.value.billing == "PROVISIONED" ? each.value.capacity.write : null
      projection_type = "ALL"

      dynamic "on_demand_throughput" {
        for_each = each.value.billing == "PAY_PER_REQUEST" ? { this = true } : {}
        content {
          max_read_request_units  = each.value.capacity.read
          max_write_request_units = each.value.capacity.write
        }
      }
    }
  }

  dynamic "ttl" {
    for_each = each.value.ttl_enabled ? { this = true } : {}
    content {
      attribute_name = "ttl"
      enabled        = true
    }
  }

  server_side_encryption {
    enabled     = each.value.encryption
    kms_key_arn = aws_kms_key.dynamodb_keys[each.key].arn
  }

  point_in_time_recovery {
    enabled = each.value.point_in_time_recovery
  }

  lifecycle {
    ignore_changes = [read_capacity, write_capacity]
  }
}

# Read
resource "aws_appautoscaling_target" "dynamodb_tables_read_target" {
  for_each           = local.dynamodb_autoscaling
  max_capacity       = each.value.autoscaling.max
  min_capacity       = each.value.autoscaling.min
  resource_id        = "table/${aws_dynamodb_table.dynamodb_tables["${each.key}"].name}"
  scalable_dimension = "dynamodb:table:ReadCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "dynamodb_tables_read_policy" {
  for_each           = local.dynamodb_autoscaling
  name               = "DynamoDBReadCapacityUtilization:${each.key}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.dynamodb_tables_read_target[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.dynamodb_tables_read_target[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.dynamodb_tables_read_target[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBReadCapacityUtilization"
    }
    target_value = each.value.autoscaling.rw_target
  }
}

resource "aws_appautoscaling_target" "dynamodb_sgi_read_target" {
  for_each           = local.dynamodb_sgi_autoscaling
  max_capacity       = each.value.autoscaling.max
  min_capacity       = each.value.autoscaling.min
  resource_id        = "table/${aws_dynamodb_table.dynamodb_tables["${each.value.table}"].name}/index/${each.value.name}"
  scalable_dimension = "dynamodb:index:ReadCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "dynamodb_sgi_read_policy" {
  for_each           = local.dynamodb_sgi_autoscaling
  name               = "DynamoDBReadCapacityUtilization:${each.key}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.dynamodb_sgi_read_target[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.dynamodb_sgi_read_target[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.dynamodb_sgi_read_target[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBReadCapacityUtilization"
    }
    target_value = each.value.autoscaling.rw_target
  }
}

# Write
resource "aws_appautoscaling_target" "dynamodb_tables_write_target" {
  for_each           = local.dynamodb_autoscaling
  max_capacity       = each.value.autoscaling.max
  min_capacity       = each.value.autoscaling.min
  resource_id        = "table/${aws_dynamodb_table.dynamodb_tables["${each.key}"].name}"
  scalable_dimension = "dynamodb:table:WriteCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "dynamodb_tables_write_policy" {
  for_each           = local.dynamodb_autoscaling
  name               = "DynamoDBWriteCapacityUtilization:${each.key}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.dynamodb_tables_write_target[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.dynamodb_tables_write_target[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.dynamodb_tables_write_target[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBWriteCapacityUtilization"
    }
    target_value = each.value.autoscaling.rw_target
  }
}

resource "aws_appautoscaling_target" "dynamodb_sgi_write_target" {
  for_each           = local.dynamodb_sgi_autoscaling
  max_capacity       = each.value.autoscaling.max
  min_capacity       = each.value.autoscaling.min
  resource_id        = "table/${aws_dynamodb_table.dynamodb_tables["${each.value.table}"].name}/index/${each.value.name}"
  scalable_dimension = "dynamodb:index:WriteCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "dynamodb_sgi_write_policy" {
  for_each           = local.dynamodb_sgi_autoscaling
  name               = "DynamoDBWriteCapacityUtilization:${each.key}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.dynamodb_sgi_write_target[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.dynamodb_sgi_write_target[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.dynamodb_sgi_write_target[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBWriteCapacityUtilization"
    }
    target_value = each.value.autoscaling.rw_target
  }
}

resource "aws_kms_key" "dynamodb_keys" {
  for_each = { for k, v in local.dynamodb_tables : k => v if lookup(v, "encryption", false) }

  description             = "KMS key for DynamoDB Server Side Encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "dynamodb_key_aliases" {
  for_each      = aws_kms_key.dynamodb_keys
  name          = "alias/${var.client}-${each.key}-key"
  target_key_id = aws_kms_key.dynamodb_keys[each.key].key_id
}

