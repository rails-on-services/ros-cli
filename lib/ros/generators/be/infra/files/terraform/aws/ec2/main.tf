resource "aws_security_group" "lb" {
  name_prefix = "allow-lb-public"
  description = "Allow access load balancer from public internete"

  vpc_id = var.vpc_id
  tags   = var.tags

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ec2" {
  name_prefix = "allow-public"
  description = "Allow access from public internet"

  vpc_id = var.vpc_id

  tags = var.tags

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # allow load balancer to reach the instance
  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.lb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_ami" "this" {
  most_recent = true

  filter {
    name   = "name"
    values = [local.ami_filter_name_map[var.ec2_ami_distro]]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = [local.ami_owner_map[var.ec2_ami_distro]]
}

resource "random_id" "ec2" {
  byte_length = 8
}

resource "aws_instance" "this" {
  ami                    = data.aws_ami.this.id
  instance_type          = var.ec2_instance_type
  subnet_id              = var.subnet_ids[0]
  key_name               = var.ec2_key_pair
  vpc_security_group_ids = [aws_security_group.ec2.id]

  root_block_device {
    volume_type = "gp2"
    volume_size = 50
  }

  user_data = templatefile("${path.module}/templates/userdata-${var.ec2_ami_distro}.tpl", {
    ssh_public_keys = var.ssh_public_keys,
    project_name    = var.project_name
  })

  tags = merge(var.tags, {
    Name = "${var.name_prefix} ${random_id.ec2.hex}"
  })
}

resource "aws_eip" "this" {
  vpc  = true
  tags = var.tags
}

resource "aws_eip_association" "this" {
  instance_id   = aws_instance.this.id
  allocation_id = aws_eip.this.id
}

resource "aws_lb_target_group" "this" {
  name_prefix = var.name_prefix
  protocol    = "HTTP"
  vpc_id      = var.vpc_id

  # the nginx listens on port 3000
  port = 3000

  health_check {
    path              = "/healthz"
    matcher           = "200"
    interval          = 10
    healthy_threshold = 2
  }
}

resource "aws_lb_target_group_attachment" "this" {
  target_group_arn = aws_lb_target_group.this.arn
  target_id        = aws_instance.this.id
}

resource "aws_lb" "this" {
  name_prefix        = var.name_prefix
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb.id]
  subnets            = var.subnet_ids

  tags = var.tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = var.aws_cert_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

resource "aws_route53_record" "lb" {
  count   = var.route53_zone_id != "" && length(var.lb_dns_hostnames) != 0 ? length(var.lb_dns_hostnames) : 0
  zone_id = var.route53_zone_id
  name    = var.lb_dns_hostnames[count.index]
  type    = "CNAME"
  ttl     = "300"
  records = [aws_lb.this.dns_name]
}
