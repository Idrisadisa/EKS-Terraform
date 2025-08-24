############################################
# Provider (US East 1)
############################################
provider "aws" {
  region = "us-east-1"
}

############################################
# Networking
############################################
resource "aws_vpc" "powerdevops_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "idris-powerdevops-vpc"
    Project     = "powerdevops"
    Environment = "dev"
    Owner       = "Idris Adisa"
    ManagedBy   = "Terraform"
  }
}

resource "aws_subnet" "powerdevops_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.powerdevops_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.powerdevops_vpc.cidr_block, 8, count.index)
  availability_zone       = element(["us-east-1a", "us-east-1b"], count.index)
  map_public_ip_on_launch = true

  tags = {
    Name        = "idris-powerdevops-subnet-${count.index}"
    Project     = "powerdevops"
    Environment = "dev"
    Owner       = "Idris Adisa"
    ManagedBy   = "Terraform"
    Tier        = "public"
  }
}

resource "aws_internet_gateway" "powerdevops_igw" {
  vpc_id = aws_vpc.powerdevops_vpc.id

  tags = {
    Name        = "idris-powerdevops-igw"
    Project     = "powerdevops"
    Environment = "dev"
    Owner       = "Idris Adisa"
    ManagedBy   = "Terraform"
  }
}

resource "aws_route_table" "powerdevops_route_table" {
  vpc_id = aws_vpc.powerdevops_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.powerdevops_igw.id
  }

  tags = {
    Name        = "idris-powerdevops-rtb-public"
    Project     = "powerdevops"
    Environment = "dev"
    Owner       = "Idris Adisa"
    ManagedBy   = "Terraform"
  }
}

resource "aws_route_table_association" "a" {
  count          = 2
  subnet_id      = aws_subnet.powerdevops_subnet[count.index].id
  route_table_id = aws_route_table.powerdevops_route_table.id
}

############################################
# Security Groups
############################################
resource "aws_security_group" "powerdevops_cluster_sg" {
  name        = "idris-powerdevops-cluster-sg"
  description = "Security group for EKS control plane"
  vpc_id      = aws_vpc.powerdevops_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "idris-powerdevops-cluster-sg"
    Project     = "powerdevops"
    Environment = "dev"
    Owner       = "Idris Adisa"
    ManagedBy   = "Terraform"
  }
}

resource "aws_security_group" "powerdevops_node_sg" {
  name        = "idris-powerdevops-node-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = aws_vpc.powerdevops_vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "idris-powerdevops-node-sg"
    Project     = "powerdevops"
    Environment = "dev"
    Owner       = "Idris Adisa"
    ManagedBy   = "Terraform"
  }
}

############################################
# IAM for EKS
############################################
resource "aws_iam_role" "powerdevops_cluster_role" {
  name = "idris-powerdevops-cluster-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "eks.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  tags = {
    Project     = "powerdevops"
    Environment = "dev"
    Owner       = "Idris Adisa"
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "powerdevops_cluster_role_policy" {
  role       = aws_iam_role.powerdevops_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# CORRECT (optional but fine to keep)
resource "aws_iam_role_policy_attachment" "powerdevops_cluster_vpc_controller" {
  role       = aws_iam_role.powerdevops_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

resource "aws_iam_role" "powerdevops_node_group_role" {
  name = "idris-powerdevops-node-group-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  tags = {
    Project     = "powerdevops"
    Environment = "dev"
    Owner       = "Idris Adisa"
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "powerdevops_node_group_role_policy" {
  role       = aws_iam_role.powerdevops_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "powerdevops_node_group_cni_policy" {
  role       = aws_iam_role.powerdevops_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "powerdevops_node_group_registry_policy" {
  role       = aws_iam_role.powerdevops_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

############################################
# EKS Cluster & Node Group
############################################
resource "aws_eks_cluster" "powerdevops" {
  name     = "idris-powerdevops-cluster"
  role_arn = aws_iam_role.powerdevops_cluster_role.arn

  vpc_config {
    subnet_ids         = aws_subnet.powerdevops_subnet[*].id
    security_group_ids = [aws_security_group.powerdevops_cluster_sg.id]
  }

  tags = {
    Project     = "powerdevops"
    Environment = "dev"
    Owner       = "Idris Adisa"
    ManagedBy   = "Terraform"
  }

  depends_on = [
    aws_iam_role_policy_attachment.powerdevops_cluster_role_policy,
    aws_iam_role_policy_attachment.powerdevops_cluster_vpc_controller
  ]
}

resource "aws_eks_node_group" "powerdevops" {
  cluster_name    = aws_eks_cluster.powerdevops.name
  node_group_name = "idris-powerdevops-node-group"
  node_role_arn   = aws_iam_role.powerdevops_node_group_role.arn
  subnet_ids      = aws_subnet.powerdevops_subnet[*].id

  scaling_config {
    desired_size = 3
    max_size     = 3
    min_size     = 3
  }

  instance_types = ["c7i-flex.large"]

  remote_access {
    ec2_ssh_key               = var.ssh_key_name
    source_security_group_ids = [aws_security_group.powerdevops_node_sg.id]
  }

  tags = {
    Project     = "powerdevops"
    Environment = "dev"
    Owner       = "Idris Adisa"
    ManagedBy   = "Terraform"
  }

  depends_on = [
    aws_iam_role_policy_attachment.powerdevops_node_group_role_policy,
    aws_iam_role_policy_attachment.powerdevops_node_group_cni_policy,
    aws_iam_role_policy_attachment.powerdevops_node_group_registry_policy
  ]
}
