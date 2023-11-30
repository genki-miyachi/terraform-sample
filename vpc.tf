# https://kleinblog.net/ecs-ecr-hello-world.html
# これを再現してみる

# ==========================
# AWSプロバイダの定義
# ==========================
provider "aws" {
  region = "ap-northeast-1"
}

# ==========================
# IAM Roles
# ==========================
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ecs-tasks.amazonaws.com",
      },
    }],
  })
}

# Attach AmazonECSTaskExecutionRolePolicy to IAM Role
resource "aws_iam_policy_attachment" "ecs_task_execution_policy_attachment" {
  name       = "ecs-task-execution-policy-attachment"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  roles      = [aws_iam_role.ecs_task_execution_role.name]
}

# Attach AmazonECSTaskExecutionRolePolicy to IAM Role
resource "aws_iam_policy_attachment" "ecs_task_code_deploy_attachment" {
  name       = "ecs-task-code-deploy-attachment"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
  roles      = [aws_iam_role.ecs_task_execution_role.name]
}

# Attach AmazonEC2ContainerRegistryReadOnly to IAM Role
resource "aws_iam_policy_attachment" "ecs_ecr_read_only_attachment" {
  name       = "ecs-ecr-read-only-attachment"
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  roles      = [aws_iam_role.ecs_task_execution_role.name]
}

# ==========================
# ECR Repository
# ==========================
resource "aws_ecr_repository" "main" {
  name = "hello-world-ecs-test"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# ==========================
# VPC
# ==========================
resource "aws_vpc" "main" { # "main" という命名を行う
  cidr_block = "192.168.20.0/24"

  tags = {
    Name = "hello-world-ecs-test"
  }
}

# ==========================
# Subnet
# ==========================
resource "aws_subnet" "main" { # 別のリソースであれば命名が被っていても問題ないです
  vpc_id     = "${aws_vpc.main.id}" # aws_vpc.mainでmainと命名されたVPCを参照し、そのVPCのIDを取得する
  cidr_block = "192.168.20.0/25"
  availability_zone = "ap-northeast-1a"

  tags = {
    Name = "hello-world-ecs-test-public-1a"
  }
}

# ==========================
# Internet GateWay
# ==========================
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "hello-world-ecs-test-igw"
  }
}

# ==========================
# Route Table
# ==========================
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "hello-world-ecs-test-public-1a-rt"
  }
}

# Subnet と RouteTable を関連付ける
resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

# ==========================
# ECS Cluster
# ==========================
resource "aws_ecs_cluster" "main" {
  name = "hello-world-ecs-test-cluster"
}

# ==========================
# ECS Task Definition
# ==========================
resource "aws_ecs_task_definition" "main" {
  family                   = "hello-world-ecs-test-task-definition"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name  = "hello-world-ecs-test-nginx"
    image = aws_ecr_repository.main.repository_url
    cpu   = 0
    portMappings = [{
      containerPort = 80,
      hostPort      = 80,
      protocol      = "tcp",
    }]
    essential  = true
    entryPoint = []
    command = []
    environment = []
    mountPoints = []
    volumesFrom = []
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/hello-world-ecs-test-task-definition"
        "awslogs-region"        = "ap-northeast-1"
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

# ==========================
# ECS Service
# ==========================
resource "aws_ecs_service" "main" {
  name             = "hello-world-ecs-test-service"
  cluster          = aws_ecs_cluster.main.id
  task_definition  = aws_ecs_task_definition.main.arn
  desired_count    = 1
  launch_type      = "FARGATE"
  platform_version = "LATEST"

  network_configuration {
    subnets          = [aws_subnet.main.id]
    security_groups  = [aws_security_group.main.id]
    assign_public_ip = true
  }
}

# ==========================
# Security Group
# ==========================
resource "aws_security_group" "main" {
  name        = "hello-world-ecs-test-sg"
  description = "Example Security Group"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

