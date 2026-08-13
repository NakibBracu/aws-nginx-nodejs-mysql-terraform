terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------
# VPC
# ---------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main-vpc"
  }
}

# ---------------------------------------------------------
# Internet Gateway
# ---------------------------------------------------------

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

# ---------------------------------------------------------
# Public Subnet
# ---------------------------------------------------------

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet"
  }
}

# ---------------------------------------------------------
# Private Subnet
# ---------------------------------------------------------

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = var.availability_zone

  tags = {
    Name = "private-subnet"
  }
}

# ---------------------------------------------------------
# Public Route Table
# ---------------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------
# NAT Gateway
# ---------------------------------------------------------

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "nat-eip"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  depends_on = [
    aws_internet_gateway.igw
  ]

  tags = {
    Name = "main-nat-gateway"
  }
}

# ---------------------------------------------------------
# Private Route Table
# ---------------------------------------------------------

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "private-route-table"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# ---------------------------------------------------------
# Security Group - Nginx
# ---------------------------------------------------------

resource "aws_security_group" "nginx" {
  name        = "nginx-sg"
  description = "Security group for Nginx"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
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

  tags = {
    Name = "nginx-sg"
  }
}

# ---------------------------------------------------------
# Security Group - Application Nodes
# ---------------------------------------------------------

resource "aws_security_group" "nodes" {
  name        = "nodes-sg"
  description = "Security group for Node EC2 instances"
  vpc_id      = aws_vpc.main.id

  # SSH only from Nginx/public host
  ingress {
    description     = "SSH from Nginx"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.nginx.id]
  }

  # Node.js application - Node 1
  ingress {
    description     = "Node.js App 5001"
    from_port       = 5001
    to_port         = 5001
    protocol        = "tcp"
    security_groups = [aws_security_group.nginx.id]
  }

  # Node.js application - Node 2
  ingress {
    description     = "Node.js App 5002"
    from_port       = 5002
    to_port         = 5002
    protocol        = "tcp"
    security_groups = [aws_security_group.nginx.id]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nodes-sg"
  }
}

# ---------------------------------------------------------
# Security Group - MySQL
# ---------------------------------------------------------

resource "aws_security_group" "mysql" {
  name        = "mysql-sg"
  description = "Security group for MySQL"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from application nodes"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.nodes.id]
  }

  ingress {
    description     = "SSH from Nginx"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.nginx.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "mysql-sg"
  }
}

# ---------------------------------------------------------
# Ubuntu 24.04 LTS AMI
# ---------------------------------------------------------

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# ---------------------------------------------------------
# Nginx EC2
# ---------------------------------------------------------

resource "aws_instance" "nginx" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.nginx.id]
  associate_public_ip_address = true

  key_name = var.key_name

  tags = {
    Name = "Nginx-EC2"
    Role = "nginx"
  }
}

# ---------------------------------------------------------
# Node 1 EC2
# ---------------------------------------------------------

resource "aws_instance" "node1" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.nodes.id]

  key_name = var.key_name

  tags = {
    Name = "Node1-EC2"
    Role = "application"
  }
}

# ---------------------------------------------------------
# Node 2 EC2
# ---------------------------------------------------------

resource "aws_instance" "node2" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.nodes.id]

  key_name = var.key_name

  tags = {
    Name = "Node2-EC2"
    Role = "application"
  }
}

# ---------------------------------------------------------
# MySQL EC2
# ---------------------------------------------------------

resource "aws_instance" "mysql" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.mysql.id]

  key_name = var.key_name

  tags = {
    Name = "MySQL-EC2"
    Role = "database"
  }
}