provider "aws" {
  region = "us-east-1"
}

# Generate a new key pair
resource "tls_private_key" "example" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = tls_private_key.example.public_key_openssh
}

# Save the private key to a local file
resource "local_file" "private_key_pem" {
  content  = tls_private_key.example.private_key_pem
  filename = "${path.module}/deployer-key.pem"
}

# Create a VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

# Create a subnet with auto-assign public IP enabled
resource "aws_subnet" "subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a" # Change as needed
  map_public_ip_on_launch = true
}

# Create an internet gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

# Create a route table
resource "aws_route_table" "routetable" {
  vpc_id = aws_vpc.main.id
}

# Create a route to the internet
resource "aws_route" "internet_access" {
  route_table_id         = aws_route_table.routetable.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}

# Associate the route table with the subnet
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet.id
  route_table_id = aws_route_table.routetable.id
}

# Create a security group that allows HTTP and SSH
resource "aws_security_group" "allow_http_ssh" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Data source to get the latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux_2" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["amazon"]
}

# Create an IAM role
resource "aws_iam_role" "ec2_role" {
  name = "EC2ECRRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com",
        },
        Action = "sts:AssumeRole",
      },
    ],
  })
}

# Attach ECR policy to the role
resource "aws_iam_role_policy" "ecr_policy" {
  name   = "ECRAccessPolicy"
  role   = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetAuthorizationToken",
        ],
        Resource = "*",
      },
    ],
  })
}

# Create an instance profile
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "EC2InstanceProfile"
  role = aws_iam_role.ec2_role.name
}

# Create an EC2 instance
resource "aws_instance" "nginx" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.subnet.id
  key_name      = aws_key_pair.deployer.key_name

  associate_public_ip_address = true

  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name

  vpc_security_group_ids = [aws_security_group.allow_http_ssh.id]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras install docker -y
              service docker start
              usermod -a -G docker ec2-user

              # Install AWS CLI
              yum install -y aws-cli

              # Authenticate Docker to ECR
              aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 901407365530.dkr.ecr.us-east-1.amazonaws.com/hello_world_html

              # Pull the Docker image from ECR
              docker pull 901407365530.dkr.ecr.us-east-1.amazonaws.com/hello_world_html:latest

              # Run the Docker container
              docker run -d -p 80:80 --name nginx 901407365530.dkr.ecr.us-east-1.amazonaws.com/hello_world_html:latest
              EOF

  tags = {
    Name = "nginx-instance"
  }
}

# Output the public IP of the instance
output "instance_public_ip" {
  value = aws_instance.nginx.public_ip
}

# Output the private key
output "private_key" {
  value     = tls_private_key.example.private_key_pem
  sensitive = true
}
