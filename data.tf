data "aws_ami" "al2023_ecs_image" {
  most_recent = true
  dynamic "filter" {
    for_each = {
      name                = "al2023-ami-ecs-hvm-*"
      architecture        = "arm64"
      virtualization-type = "hvm"
    }
    content {
      name   = filter.key
      values = [filter.value]
    }
  }
  owners = ["591542846629"] # AWS
}

data "aws_ami" "al1_ecs_image" {
  most_recent = true
  dynamic "filter" {
    for_each = {
      name                = "amzn-ami-*-amazon-ecs-optimized"
      architecture        = "x86_64"
      virtualization-type = "hvm"
    }
    content {
      name   = filter.key
      values = [filter.value]
    }
  }
  owners = ["591542846629"] # AWS
}

