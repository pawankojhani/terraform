terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.12"
    }
  }
}
provider "aws" {
  region = "us-east-2"
  access_key = "my-access-key"
  secret_key = "my-secret-key"
}

resource "aws_vpc" "main" {
  cidr_block = "172.16.0.0/16"

  tags = {
    Project = "kmpg"
  }
}

resource "aws_subnet" "pub_sub" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "172.16.1.0/24"
  availability_zone       = "us-east-2a"
  map_public_ip_on_launch = true

  tags = {
    Project = "kpmg"
  }
}

resource "aws_subnet" "prv_sub" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "172.16.4.0/24"
  availability_zone       = "us-east-2a"
  map_public_ip_on_launch = false

  tags = {
    Project = "kpmg"
  }
}
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Project = "kpmg"
  }
}

resource "aws_route_table" "pub_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Project = "kpmg"
  }
}

resource "aws_route_table_association" "rt_assoc" {
  subnet_id      = aws_subnet.pub_sub.id
  route_table_id = aws_route_table.pub_rt.id
}

resource "aws_eip" "nat_eip" {
  vpc = true

  tags = {
    Project = "kpmg"
  }
}

resource "aws_nat_gateway" "ngw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.pub_sub.id

  tags = {
    Project = "kpmg"
  }
}

resource "aws_route_table" "prv_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ngw.id
  }

  tags = {
    Project = "kpmg"
  }
}

resource "aws_route_table_association" "prv_rt_assoc" {
  subnet_id      = aws_subnet.prv_sub.id
  route_table_id = aws_route_table.prv_rt.id
}

resource "aws_security_group" "general_sg" {
  description = "HTTP egress to anywhere"
  vpc_id      = aws_vpc.main.id

  tags = {
    Project = "kpmg"
  }
}

resource "aws_security_group" "bastion_sg" {
  description = "SSH ingress to Bastion and SSH egress to App"
  vpc_id      = aws_vpc.main.id

  tags = {
    Project = "kpmg"
  }
}

resource "aws_security_group" "app_sg" {
  description = "SSH ingress from Bastion and all TCP traffic ingress from ALB Security Group"
  vpc_id      = aws_vpc.main.id
  tags = {
    Project = "kpmg"
  }
}
resource "aws_security_group_rule" "out_http" {
  type              = "egress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.general_sg.id
}

resource "aws_security_group_rule" "out_ssh_bastion" {
  type                     = "egress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.bastion_sg.id
  source_security_group_id = aws_security_group.app_sg.id
}

resource "aws_security_group_rule" "out_http_app" {
  type              = "egress"
  description       = "Allow TCP internet traffic egress from app layer"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.app_sg.id
}

resource "aws_security_group_rule" "in_ssh_bastion_from_anywhere" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.bastion_sg.id
}

resource "aws_security_group_rule" "in_ssh_app_from_bastion" {
  type                     = "ingress"
  description              = "Allow SSH from a Bastion Security Group"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.app_sg.id
  source_security_group_id = aws_security_group.bastion_sg.id
}

resource "aws_key_pair" "key-kpmg" {
  key_name   = "key-kpmg"
  public_key = file("${path.module}/id_rsa.pub")
}


resource "aws_instance" "jump_server" {
  ami                    = "ami-011d03b8ddcef80fd"
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.key-kpmg.key_name
  availability_zone      = "us-east-2a"
  subnet_id              = aws_subnet.pub_sub.id
  vpc_security_group_ids = [aws_security_group.general_sg.id, aws_security_group.bastion_sg.id]

  tags = {
    Project = "kpmg"
  }
}

resource "aws_instance" "app_server" {
  ami                    = "ami-011d03b8ddcef80fd"
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.key-kpmg.key_name
  availability_zone      = "us-east-2a"
  subnet_id              = aws_subnet.prv_sub.id
  vpc_security_group_ids = [aws_security_group.general_sg.id, aws_security_group.app_sg.id]

  tags = {
    Project = "kpmg"
  }
}

resource "aws_lb" "external-elb" {
  name               = "External-LB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.app_sg.id]
  subnets            = [aws_subnet.pub_sub.id, aws_subnet.prv_sub.id]
}

resource "aws_lb_target_group" "external-elb" {
  name     = "ALB-TG"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_target_group_attachment" "external-elb1" {
  target_group_arn = aws_lb_target_group.external-elb.arn
  target_id        = aws_instance.app_server.id
  port             = 80

  depends_on = [
    aws_instance.app_server,
  ]
}

resource "aws_lb_listener" "external-elb" {
  load_balancer_arn = aws_lb.external-elb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.external-elb.arn
  }
}

resource "aws_db_instance" "kpmg-rds" {
  allocated_storage    = 10
  engine               = "mysql"
  engine_version       = "8.0.20"
  instance_class       = "db.t3.micro"
  name                 = "kpmg-t"
  username             = "kpmg-devops"
  password             = "kpmg-devops"
  parameter_group_name = "default.mysql8.0"
  skip_final_snapshot  = true
}

output "lb_dns_name" {
  description = "The DNS name of the load balancer"
  value       = aws_lb.external-elb.dns_name
}


