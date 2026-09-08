terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "cloud-ops-lab-tfstate"
    key    = "phase9-observability/terraform.tfstate"
    region = "ap-northeast-1"
  }
}

provider "aws" {
  region = var.region
}

# ── 既存リソースをタグで検索 ──────────────────────────
data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = ["${var.project_name}-vpc"]
  }
}

data "aws_subnet" "public" {
  filter {
    name   = "tag:Name"
    # values = ["${var.project_name}-public-subnet"]
    values = ["${var.project_name}-public-1a"]
  }
}

# ── Security Group ────────────────────────────────────
resource "aws_security_group" "monitoring" {
  name        = "${var.project_name}-monitoring-sg"
  description = "Prometheus and Grafana"
  vpc_id      = data.aws_vpc.main.id

  # Grafana
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Prometheus（自分自身の確認用。本番では閉じる）
  ingress {
    from_port   = 9090
    to_port     = 9090
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
    Name    = "${var.project_name}-monitoring-sg"
    Project = var.project_name
    Phase   = "9"
  }
}

# ── EC2（監視サーバー）────────────────────────────────
resource "aws_instance" "monitoring" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.monitoring.id]
  associate_public_ip_address = true
  iam_instance_profile        = "cloud-ops-lab-ec2-ssm-role"  # ← 追加

  user_data = file("${path.module}/user_data.sh")

  tags = {
    Name    = "${var.project_name}-monitoring"
    Project = var.project_name
    Phase   = "9"
  }
}
