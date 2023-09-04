terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}


# Configure the AWS Provider
provider "aws" {
    region = var.region
    profile = var.profile_name
}

# Create a VPC
resource "aws_vpc" "uat-vpc" {
  cidr_block  = "178.0.0.0/16"

  tags = {
    Name = "uat-vpc"
  }
}

resource "aws_internet_gateway" "uat-gw" {
  vpc_id = aws_vpc.uat-vpc.id

  tags = {
    Name = "uat-igw"
  }
}

resource "aws_subnet" "uat-public-subnet" {
  vpc_id     = aws_vpc.uat-vpc.id
  cidr_block = ["10.0.0.0/20", "10.0.128.0/20"]
  map_public_ip_on_launch = true
  availability_zone = "eu-west-2a"

  tags = {
    Name = "uat-public_subnet"
  }
}

resource "aws_subnet" "uat-private-subnet" {
  vpc_id     = aws_vpc.uat-vpc.id
  cidr_block = ["10.0.16.0/20", "10.0.144.0/20"]
  map_public_ip_on_launch = true

  tags = {
    Name = "uat-private-subnet"
  }
}


resource "aws_route_table" "uat_public_rt" {
  vpc_id = aws_vpc.uat_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.uat_gw.id
  }

  tags = {
    Name = "uat-public_rt"
  }
}

resource "aws_route_table_association" "uat_public_rt_asso" {
  subnet_id      = aws_subnet.uat_public_subnet.id
  route_table_id = aws_route_table.uat_public_rt.id
}

resource "aws_instance" "uat_env" {
    ami = "ami-0eb260c4d5475b901"
    instance_type = var.instance_type
    subnet_id = aws_subnet.uat_public_subnet.id
    security_groups = [aws_security_group.uat_sg.id]

    user_data = data.template_file.user_data.rendered

    tags = {
        Name = "terraform-uat_env"
    }
}

/*
terraform {
  backend "s3" {
    bucket = "works-up-and-running-state"
    key = "stage/services/webserver-cluster/terraform.tfstate"
    region = "eu-west-2"
    dynamodb_table = "works-up-and-running-state"
    encrypt = true
  }
}
*/

data "template_file" "user_data" {
  template = file("user-data.sh")

  vars = {
    #server_port = var.server_port
    db_address = data.terraform_remote_state.db.outputs.address
    db_port = data.terraform_remote_state.db.outputs.port
  }
}

data "terraform_remote_state" "db" {
  backend = "s3"

  config ={
    bucket = "works-up-and-running-state"
    key = "staging/data-stores/mysql/terraform.tfstate"
    region = "eu-west-2"
  }
}


resource "aws_launch_configuration" "uat-lcg" {
  image_id        = "ami-0fb653ca2d3203ac1"
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.uat-sg.id]

  # Render the User Data script as a template
  user_data = templatefile("user-data.sh", {
    server_port = var.server_port
    db_address  = data.terraform_remote_state.db.outputs.address
    db_port     = data.terraform_remote_state.db.outputs.port
  })

  # Required when using a launch configuration with an auto scaling group.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "uat-asg" {
  launch_configuration = aws_launch_configuration.uat-lcg.name
  vpc_zone_identifier  = data.aws_subnets.default.ids

  target_group_arns = [aws_lb_target_group.asg.arn]
  health_check_type = "ELB"

  min_size = 1
  max_size = 3

  tag {
    key                 = "Name"
    value               = "uat-asg"
    propagate_at_launch = true
  }
}

resource "aws_security_group" "uat-sg" {
  name = "uat-fence"

  ingress {
    from_port   = "22"
    to_port     = "22"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = "80"
    to_port     = "80"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_elb" "uat-elb" {
  name               = "uat-elb"
  subnets            = data.aws_subnets.default.ids
  security_groups    = [aws_security_group.uat-sg.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port              = 80
  protocol          = "HTTP"

  # By default, return a simple 404 page
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code  = 404
    }
  }
}

resource "aws_lb_target_group" "asg" {
  name     = var.alb_name
  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  condition {
    path_pattern {
      values = ["*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}

data "terraform_remote_state" "db" {
  backend = "s3"

  config = {
    bucket = var.db_remote_state_bucket
    key    = var.db_remote_state_key
    region = "us-east-2"
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}
