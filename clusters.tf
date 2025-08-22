resource "aws_ecs_cluster" "clusters" {
  for_each = local.clusters
  name     = "${var.client}-${each.key}"
}

resource "aws_launch_template" "clusters" {
  for_each = local.clusters

  name_prefix = "${var.client}-${each.key}-"
  image_id    = each.value.image.id
  # image_id    = data.aws_ami.al2023_ecs_image.id
  instance_type = each.value.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.cluster_profile["${each.key}"].name
  }


  user_data = base64encode(<<-EOS
    #!/bin/bash
    echo "[INFO] Redirecting all user_data output to /var/log/user-data.log"
    # echo "=== Test output ===" | tee /var/log/user-data.log
    exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

    echo "[INFO] Updating cache and installing dependencies"
    yum makecache -q && yum update -q -y
    yum install -y util-linux python27-requests wget ecs-init

    echo "[INFO] Installing Logging Tools"
    # yum install -y amazon-cloudwatch-agent # cloudwatch is only available on al2 and forwards
    wget https://amazoncloudwatch-agent.s3.amazonaws.com/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
    sudo rpm -U ./amazon-cloudwatch-agent.rpm

    echo "[INFO] Configuring Cloudwatch Agent"
    cat <<EOF | tee /tmp/cloudwatch-agent-config.json
    {
      "logs": {
        "logs_collected": {
          "files": {
            "collect_list": [
              {
                "file_path": "/var/log/user-data.log",
                "log_group_name": "${aws_cloudwatch_log_group.cluster_user_data_logs["${each.key}"].name}",
                "log_stream_name": "{instance_id}"
              },
              {
                "file_path": "/var/log/ecs/ecs-agent.log",
                "log_group_name": "${aws_cloudwatch_log_group.cluster_ecs_agent_logs["${each.key}"].name}",
                "log_stream_name": "{instance_id}"
              }
            ]
          }
        }
      }
    }
    EOF

    echo "[INFO] Starting Cloudwatch Agent"
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config -m ec2 -s -c file:/tmp/cloudwatch-agent-config.json

    echo "[INFO] Setting ECS Agent settings..."
    cat <<EOF | tee -a /etc/ecs/ecs.config
    ECS_CLUSTER=${var.client}-${each.key}
    ECS_DISABLE_IMAGE_CLEANUP=false
    ECS_IMAGE_CLEANUP_INTERVAL=${each.value.task_cleanup.interval}
    ECS_ENGINE_TASK_CLEANUP_WAIT_DURATION=${each.value.task_cleanup.wait_duration}
    ECS_IMAGE_MINIMUM_CLEANUP_AGE=${each.value.task_cleanup.image_age}
    ECS_LOGLEVEL=info
    EOF

    echo "[INFO] Restarting ECS Service"
    stop ecs
    /usr/libexec/amazon-ecs-init reload-cache
    start ecs
    EOS
  )
}

resource "aws_autoscaling_group" "clusters" {
  for_each = local.clusters

  name               = "${var.client}-${each.key}"
  availability_zones = ["${var.region}a"]
  desired_capacity   = each.value.autoscaling.desired
  min_size           = each.value.autoscaling.min
  max_size           = each.value.autoscaling.max

  launch_template {
    id      = aws_launch_template.clusters["${each.key}"].id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      instance_warmup = "60"
    }
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}

# Cloudwatch
resource "aws_cloudwatch_log_group" "cluster_user_data_logs" {
  for_each = local.clusters

  name              = "/ec2/${each.key}-user-data-logs"
  retention_in_days = each.value.log_retention_in_days
}

resource "aws_cloudwatch_log_group" "cluster_ecs_agent_logs" {
  for_each = local.clusters

  name              = "/ec2/${each.key}-ecs-agent-logs"
  retention_in_days = each.value.log_retention_in_days
}

# IAM
resource "aws_iam_role" "cluster_roles" {
  for_each = local.clusters

  name               = "${var.client}-${each.key}-role"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "cw_agent_attach" {
  for_each = local.clusters

  role       = aws_iam_role.cluster_roles["${each.key}"].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# TODO: Container Instance needs ecs:RegisterContainerInstance to register itself as a container instance

resource "aws_iam_instance_profile" "cluster_profile" {
  for_each = local.clusters

  name = "${var.client}-${each.key}-profile"
  role = aws_iam_role.cluster_roles["${each.key}"].name
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role_policy" "cluster_cloudwatch_policies" {
  for_each = local.clusters

  name = "${var.client}-${each.key}-cloudwatch-policy"
  role = aws_iam_role.cluster_roles["${each.key}"].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = [
        "arn:aws:logs:*:*:log-group:${aws_cloudwatch_log_group.cluster_user_data_logs["${each.key}"].name}",
        "arn:aws:logs:*:*:log-group:${aws_cloudwatch_log_group.cluster_ecs_agent_logs["${each.key}"].name}",
      ]
    }]
  })
}
