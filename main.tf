###############################################################
# EC2 Instance + AMI + Auto Scaling Group + ALB Integration
# For Roboshop Component Deployment (e.g., catalogue, user, frontend)
###############################################################

# ------------------------------------------------------------
# 1. CREATE BASE EC2 INSTANCE
# ------------------------------------------------------------
resource "aws_instance" "main" {
  ami                    = local.ami_id            # Base AMI ID (RHEL/DevOps)
  instance_type          = "t3.micro"              # Instance type (small and cost-effective)
  vpc_security_group_ids = [local.sg_id]           # Security group for this component
  subnet_id              = local.private_subnet_id # Launch in private subnet

  # Attach consistent tags for identification and management
  tags = merge(
    local.common_tags,
    {
      Name = "${local.common_name_suffix}-${var.component}" # e.g., roboshop-dev-catalogue
    }
  )
}

# ------------------------------------------------------------
# 2. RUN BOOTSTRAP SCRIPT VIA REMOTE-EXEC (ANSIBLE SETUP)
# ------------------------------------------------------------
resource "terraform_data" "main" {
  triggers_replace = [aws_instance.main.id] # Ensures re-provisioning if EC2 is replaced

  # SSH connection details for remote execution
  connection {
    type     = "ssh"
    user     = "ec2-user"
    password = "DevOps321"                  # Simplified demo password (in practice use key pair or SSM)
    host     = aws_instance.main.private_ip # Connect to EC2 using private IP
  }

  # Copy bootstrap.sh script from local machine to EC2
  provisioner "file" {
    source      = "bootstrap.sh"      # Local file to copy
    destination = "/tmp/bootstrap.sh" # Destination path on EC2
  }

  # Execute the script remotely with required arguments
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/bootstrap.sh",
      "sudo sh /tmp/bootstrap.sh ${var.component} ${var.environment}"
    ]
  }
}

# ------------------------------------------------------------
# 3. STOP THE INSTANCE TO CREATE AN AMI
# ------------------------------------------------------------
resource "aws_ec2_instance_state" "main" {
  instance_id = aws_instance.main.id
  state       = "stopped"             # Required before taking an AMI
  depends_on  = [terraform_data.main] # Ensure provisioning completes first
}

# ------------------------------------------------------------
# 4. CREATE AMI (IMAGE) FROM THE CONFIGURED INSTANCE
# ------------------------------------------------------------
resource "aws_ami_from_instance" "main" {
  name               = "${local.common_name_suffix}-${var.component}-ami" # e.g., roboshop-dev-catalogue-ami
  source_instance_id = aws_instance.main.id
  depends_on         = [aws_ec2_instance_state.main] # Wait until instance is stopped

  tags = merge(
    local.common_tags,
    {
      Name = "${local.common_name_suffix}-${var.component}-ami"
    }
  )
}

# ------------------------------------------------------------
# 5. CREATE TARGET GROUP FOR LOAD BALANCER
# ------------------------------------------------------------
resource "aws_lb_target_group" "main" {
  name                 = "${local.common_name_suffix}-${var.component}"
  port                 = local.tg_port # Frontend → 80, Backends → 8080 (dynamic)
  protocol             = "HTTP"
  vpc_id               = local.vpc_id
  deregistration_delay = 60 # Wait 60s before removing instance

  # Define health check settings to monitor app health
  health_check {
    healthy_threshold   = 2
    interval            = 10
    matcher             = "200-299"               # Expected HTTP response codes
    path                = local.health_check_path # Frontend → "/", Backends → "/health"
    port                = local.tg_port
    protocol            = "HTTP"
    timeout             = 2
    unhealthy_threshold = 2
  }
}

# ------------------------------------------------------------
# 6. CREATE LAUNCH TEMPLATE
# ------------------------------------------------------------
resource "aws_launch_template" "main" {
  name                   = "${local.common_name_suffix}-${var.component}"
  image_id               = aws_ami_from_instance.main.id # Use AMI created above
  instance_type          = "t3.micro"
  vpc_security_group_ids = [local.sg_id]

  instance_initiated_shutdown_behavior = "terminate"
  update_default_version               = true # Each new AMI creates a new version of this template

  # Tags for launched instances
  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${local.common_name_suffix}-${var.component}"
    })
  }

  # Tags for attached volumes
  tag_specifications {
    resource_type = "volume"
    tags = merge(local.common_tags, {
      Name = "${local.common_name_suffix}-${var.component}"
    })
  }

  # Tags for the launch template itself
  tags = merge(local.common_tags, {
    Name = "${local.common_name_suffix}-${var.component}"
  })
}

# ------------------------------------------------------------
# 7. CREATE AUTO SCALING GROUP (ASG)
# ------------------------------------------------------------
resource "aws_autoscaling_group" "main" {
  name                      = "${local.common_name_suffix}-${var.component}"
  max_size                  = 10 # Maximum 10 instances
  min_size                  = 1  # At least 1 instance must run
  desired_capacity          = 1  # Start with one instance
  health_check_type         = "ELB"
  health_check_grace_period = 100 # Wait before marking instance unhealthy
  force_delete              = false
  vpc_zone_identifier       = local.private_subnet_ids       # Use all private subnets
  target_group_arns         = [aws_lb_target_group.main.arn] # Attach to load balancer

  # Connect the ASG to the launch template
  launch_template {
    id      = aws_launch_template.main.id
    version = aws_launch_template.main.latest_version
  }

  # Rolling update strategy: replace instances gradually
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50 # Keep at least half instances running during refresh
    }
    triggers = ["launch_template"] # Refresh triggered when new AMI is available
  }

  # Propagate tags to all instances created by ASG
  dynamic "tag" {
    for_each = merge(local.common_tags, {
      Name = "${local.common_name_suffix}-${var.component}"
    })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  timeouts {
    delete = "15m" # Allow up to 15 minutes for ASG deletion
  }
}

# ------------------------------------------------------------
# 8. AUTO SCALING POLICY (TARGET TRACKING)
# ------------------------------------------------------------
resource "aws_autoscaling_policy" "main" {
  autoscaling_group_name = aws_autoscaling_group.main.name
  name                   = "${local.common_name_suffix}-${var.component}"
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration { # Automatically adjust ASG based on average CPU utilization
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 75.0 # Target average CPU utilization (scale out above 75%)
  }
}

# ------------------------------------------------------------
# 9. CREATE ALB LISTENER RULE (ROUTING)
# ------------------------------------------------------------
resource "aws_lb_listener_rule" "main" {
  listener_arn = local.listener_arn # Dynamically uses frontend/backend ALB listener
  priority     = var.rule_priority  # Controls rule order (unique per component)

  # Forward requests to the correct target group
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  # Define routing condition based on domain/host name
  condition {
    host_header {
      values = [local.host_context] # e.g., "catalogue.backend-alb-dev.daws86s.fun"
    }
  }
}

# ------------------------------------------------------------
# 10. CLEANUP TEMPORARY EC2 INSTANCE
# ------------------------------------------------------------
resource "terraform_data" "main_local" {
  triggers_replace = [aws_instance.main.id]
  depends_on       = [aws_autoscaling_policy.main]

  # Run local command to terminate the initial EC2 used to create AMI
  provisioner "local-exec" {
    command = "aws ec2 terminate-instances --instance-ids ${aws_instance.main.id}"
  }
}
