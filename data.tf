##############################################
# FETCH LATEST RHEL-9 AMI FROM SPECIFIC OWNER
##############################################

data "aws_ami" "joindevops" {
  owners      = ["973714476881"] # AWS account ID that owns the AMI (DevOps team / custom AMI publisher)
  most_recent = true             # Ensures the latest available AMI is selected

  # Filter 1: Match AMIs with this specific name pattern
  filter {
    name   = "name"
    values = ["RHEL-9-DevOps-Practice"] # AMI name to look for
  }

  # Filter 2: Match only EBS-backed AMIs
  filter {
    name   = "root-device-type"
    values = ["ebs"] # Ensures the AMI uses EBS as root device
  }

  # Filter 3: Match only HVM virtualization type
  filter {
    name   = "virtualization-type"
    values = ["hvm"] # Hardware Virtual Machine type (common for EC2)
  }
}

##############################################
# FETCH NETWORK AND SECURITY INFO FROM SSM PARAMETER STORE
##############################################


# Fetch private subnet IDs
data "aws_ssm_parameter" "private_subnet_ids" {
  name = "/${var.project_name}/${var.environment}/private_subnet_ids"
}

# Fetch Security Group ID for 
data "aws_ssm_parameter" "sg_id" {
  name = "/${var.project_name}/${var.environment}/sg_id"
}

# Fetch VPC ID used for the project
data "aws_ssm_parameter" "vpc_id" {
  name = "/${var.project_name}/${var.environment}/vpc_id"
}


# Fetch Backend ALB Listener ARN (used for attaching target groups)
data "aws_ssm_parameter" "backend_alb_listener_arn" {
  name = "/${var.project_name}/${var.environment}/backend_alb_listener_arn"
}


# Fetch Backend ALB Listener ARN (used for attaching target groups)
data "aws_ssm_parameter" "frontend_alb_listener_arn" {
  name = "/${var.project_name}/${var.environment}/frontend_alb_listener_arn"
}

##############################################
# SUMMARY
##############################################
# This data block setup does the following:
# - Dynamically fetches the latest custom AMI for EC2 instances.
# - Retrieves network and security configuration values from AWS SSM Parameter Store.
# - Keeps the Terraform code modular and environment-agnostic (e.g., dev, prod).
# - Avoids hardcoding IDs or AMIs, allowing safe and consistent deployments.
