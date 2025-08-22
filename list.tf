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
}
