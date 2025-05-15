provider "aws" {
  region = "eu-west-1"
}

# ---- VPC ----
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"

  name = "test-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["eu-west-1a", "eu-west-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    Terraform = "true"
    Environment = "test"
  }
}

# ---- Security Group for EC2 ----
resource "aws_security_group" "ec2_sg" {
  name        = "ec2_sg"
  description = "Allow HTTP/SSH"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # SSH
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # HTTP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---- EC2 Instance ----
resource "aws_instance" "wordpress" {
  ami           = "ami-0c1c30571d2dae5c9" # Amazon Linux 2 (example, check region)
  instance_type = "t2.micro"
  subnet_id     = module.vpc.public_subnets[0]
  security_groups = [aws_security_group.ec2_sg.name]

  user_data = file("wordpress-setup.sh") # bash script to install WordPress

  tags = {
    Name = "wordpress-instance"
  }
}

# ---- RDS MySQL ----
resource "aws_db_instance" "mysql" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password123!"
  parameter_group_name = "default.mysql8.0"
  publicly_accessible  = false
  skip_final_snapshot  = true
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  db_subnet_group_name = module.vpc.database_subnet_group
}

# ---- ElastiCache Redis ----
resource "aws_elasticache_subnet_group" "redis_subnet_group" {
  name       = "redis-subnet-group"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "redis-cluster"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  subnet_group_name    = aws_elasticache_subnet_group.redis_subnet_group.name
  security_group_ids   = [aws_security_group.ec2_sg.id]
}

# ---- IAM User for Reviewer ----
resource "aws_iam_user" "review_user" {
  name = "reviewer"
}

resource "aws_iam_user_login_profile" "review_login" {
  user    = aws_iam_user.review_user.name
  pgp_key = "keybase:yourkeybaseuser" # or use a dummy for local testing
}

resource "aws_iam_policy" "limited_read" {
  name = "limited-read-only"
  path = "/"
  description = "Limited read-only access for test reviewer"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ec2:Describe*",
          "rds:Describe*",
          "elasticache:Describe*",
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "cloudwatch:GetMetricData",
          "cloudwatch:ListMetrics"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "attach_review_policy" {
  user       = aws_iam_user.review_user.name
  policy_arn = aws_iam_policy.limited_read.arn
}

# ---- Output Credentials ----
output "reviewer_login" {
  value = "https://${data.aws_caller_identity.current.account_id}.signin.aws.amazon.com/console"
}

output "reviewer_username" {
  value = aws_iam_user.review_user.name
}

output "encrypted_password" {
  value = aws_iam_user_login_profile.review_login.encrypted_password
  sensitive = true
}

data "aws_caller_identity" "current" {}

