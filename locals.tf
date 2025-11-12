###############################################################
# Local Variables for Roboshop Terraform Configuration
###############################################################
# Locals are used to define derived or reusable values
# that can be referenced throughout your Terraform code.
# This avoids repetition and makes configurations more readable.
###############################################################

locals {

  # ------------------------------------------------------------
  # Common name suffix for resources
  # Example: roboshop-dev or roboshop-prod
  # This is used to tag and name AWS resources consistently.
  # ------------------------------------------------------------
  common_name_suffix = "${var.project_name}-${var.environment}"

  # ------------------------------------------------------------
  # Private subnet ID (first subnet)
  # The SSM parameter contains a comma-separated list of subnet IDs.
  # split() converts that string into a list.
  # [0] picks the first subnet from the list.
  # ------------------------------------------------------------
  private_subnet_id = split(",", data.aws_ssm_parameter.private_subnet_ids.value)[0]

  # ------------------------------------------------------------
  # List of all private subnet IDs
  # Used when you need to refer to all subnets (e.g., in ALBs or RDS).
  # ------------------------------------------------------------
  private_subnet_ids = split(",", data.aws_ssm_parameter.private_subnet_ids.value)

  # ------------------------------------------------------------
  # VPC ID – fetched from AWS SSM Parameter Store
  # Used to attach resources to the correct VPC.
  # ------------------------------------------------------------
  vpc_id = data.aws_ssm_parameter.vpc_id.value

  # ------------------------------------------------------------
  # Security Group ID – fetched from SSM
  # Defines the default SG used for EC2 or other components.
  # ------------------------------------------------------------
  sg_id = data.aws_ssm_parameter.sg_id.value

  # ------------------------------------------------------------
  # Target Group Port
  # Uses a conditional expression (ternary operator):
  # If the component is 'frontend' → use port 80  (Frontend EC2 instance → listens on port 80;ALB Target Group (frontend) → forwards traffic on port 80)
  # Else → use port 8080  ( Backend EC2 instance → Node.js app listens on port 8080;ALB Target Group (backend) → forwards traffic on port 8080)
  # ------------------------------------------------------------
  tg_port = "${var.component}" == "frontend" ? 80 : 8080

  # ------------------------------------------------------------
  # Health Check Path for Load Balancer Target Group
  # For frontend → use root path "/" The frontend is web app(Nginx/UI server)serves pages directly on the root URL — http://frontend/.It doesn’t usually have a dedicated /health API endpoint.Therefore, the ALB checks the root path / to see if the web server responds with status code 200.
  # For backend components → use "/health" endpoint
  # ------------------------------------------------------------
  health_check_path = "${var.component}" == "frontend" ? "/" : "/health"

  # ------------------------------------------------------------
  # AMI ID for EC2 instance
  # Obtained from a data source that filters the latest AMI (joindevops).
  # ------------------------------------------------------------
  ami_id = data.aws_ami.joindevops.id

  # ------------------------------------------------------------
  # Backend ALB Listener ARN – stored in SSM
  # Used by backend services like catalogue, user, cart, etc.
  # ------------------------------------------------------------
  backend_alb_listener_arn = data.aws_ssm_parameter.backend_alb_listener_arn.value

  # ------------------------------------------------------------
  # Frontend ALB Listener ARN – stored in SSM
  # Used by the frontend service only.
  # ------------------------------------------------------------
  frontend_alb_listener_arn = data.aws_ssm_parameter.frontend_alb_listener_arn.value

  # ------------------------------------------------------------
  # If the component is frontend → use frontend ALB listener
  # Else → use backend ALB listener
  # This ensures each component connects to the correct ALB.
  # ------------------------------------------------------------
  listener_arn = "${var.component}" == "frontend" ? local.frontend_alb_listener_arn : local.backend_alb_listener_arn

  # ------------------------------------------------------------
  # If frontend → roboshop-dev.domain.com
  # Else → catalogue.backend-alb-dev.domain.com
  # Used in ALB host_header condition for each component.
  # ------------------------------------------------------------
  host_context = "${var.component}" == "frontend" ? "${var.project_name}-${var.environment}.${var.domain_name}" : "${var.component}.backend-alb-${var.environment}.${var.domain_name}"


  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Terraform   = "true"
  }
}
