locals {
  buckets = {}
  clusters = {
    # testing = {
    #   image                 = data.aws_ami.al1_ecs_image
    #   instance_type         = "t3a.nano"
    #   autoscaling           = { desired = 1, min = 1, max = 1 }
    #   task_cleanup          = { interval = "10m", wait_duration = "10m", image_age = "15m" }
    #   log_retention_in_days = 7
    # }
  }
  dynamodb_tables = {
    proxy = {
      billing                = "PROVISIONED"
      point_in_time_recovery = true
      ttl_enabled            = true
      encryption             = true
      autoscaling            = { enabled = true, min = 1, max = 4, rw_target = 70 }
      capacity               = { read = 1, write = 1 }
      hash                   = { name = "id", type = "S" }
      range                  = { enabled = false, name = "", type = "" }
      secondary_indexes = {
        "example" = {
          type  = "S"
          range = { enabled = false, name = "", type = "" }
        }
        "another-one" = {
          type  = "S"
          range = { enabled = false, name = "", type = "" }
        }
      }
    }
    # backoffice = {
    #   billing                = "PAY_PER_REQUEST"
    #   point_in_time_recovery = false
    #   ttl_enabled            = true
    #   encryption             = true
    #   autoscaling            = { enabled = false, min = 1, max = 10, rw_target = 70 }
    #   capacity               = { read = -1, write = -1 }
    #   hash                   = { name = "PK", type = "S" }
    #   range                  = { enabled = true, name = "SK", type = "S" }
    #   secondary_indexes = {
    #     "event_type-PK-index" = {
    #       hash  = { name = "event_type", type = "S" },
    #       range = { enabled = true, name = "PK", type = "S" }
    #     },
    #     "requester_id-SK-index" = {
    #       hash  = { name = "requester_id", type = "S" }
    #       range = { enabled = true, name = "SK", type = "S" }
    #     }
    #   }
    # }
  }
  dynamodb_autoscaling = { for k, v in local.dynamodb_tables : k => v if v.billing == "PROVISIONED" && v.autoscaling.enabled }
  dynamodb_sgi_autoscaling = { for e in flatten([
    for tb, cfg in local.dynamodb_autoscaling : [
      for sgi, params in lookup(cfg, "secondary_indexes", {}) : {
        id = "${tb}-${sgi}", table = tb, name = sgi, gsi = params, autoscaling = cfg.autoscaling
    }]]) : e.id => e }
}
