provider "aws" {
  region = "eu-west-1"
  profile = "tf-user"
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

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-subnet-group"
  subnet_ids = module.vpc.private_subnets
  tags = {
    Name = "rds-subnet-group"
  }
}

# ---- Security Group for EC2 ----
resource "aws_security_group" "ec2_sg" {
  name        = "ec2_sg"
  description = "Allow HTTP/SSH from internet"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # SSH
    description = "SSH from anywhere (consider restricting to specific IPs)"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # HTTP
    description = "HTTP from anywhere"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  
  tags = {
    Name = "ec2-security-group"
    Environment = "test"
  }
}

# ---- Security Group for RDS ----
resource "aws_security_group" "rds_sg" {
  name        = "rds_sg"
  description = "Allow MySQL access from EC2"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
    description     = "MySQL from EC2 instances"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  
  tags = {
    Name = "rds-security-group"
    Environment = "test"
  }
}

# ---- Security Group for Redis ----
resource "aws_security_group" "redis_sg" {
  name        = "redis_sg"
  description = "Allow Redis access from EC2"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
    description     = "Redis from EC2 instances"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  
  tags = {
    Name = "redis-security-group"
    Environment = "test"
  }
}

# ---- EC2 Instance ----
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "wordpress" {
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = "t2.micro"
  subnet_id                   = module.vpc.public_subnets[0]
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  #key_name                    = "your-key-pair-name" 

  user_data = templatefile("${path.module}/wordpress-setup.sh", {
    WORDPRESS_DB_NAME      = "wordpressdb"
    WORDPRESS_DB_USER      = "admin"
    WORDPRESS_DB_PASSWORD  = "password123!"
    WORDPRESS_DB_HOST      = aws_db_instance.mysql.address
    WORDPRESS_REDIS_HOST   = aws_elasticache_cluster.redis.cache_nodes[0].address
    WORDPRESS_REDIS_PORT   = "6379"
    WORDPRESS_ADMIN_USER   = "admin"
    WORDPRESS_ADMIN_PASS   = "admin123"
    WORDPRESS_ADMIN_EMAIL  = "test@example.com"
  })

  tags = {
    Name = "wordpress-instance"
  }
}

# ---- RDS MySQL ----
resource "aws_db_instance" "mysql" {
  db_name              = "wordpressdb"
  engine               = "mysql"
  instance_class       = "db.t3.micro"
  allocated_storage    = 20
  username             = "admin"
  password             = "password123!"
  parameter_group_name = "default.mysql8.0"
  publicly_accessible  = false
  skip_final_snapshot  = true

  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  
  tags = {
    Name = "wordpress-mysql"
    Environment = "test"
  }
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
  security_group_ids   = [aws_security_group.redis_sg.id]
  
  tags = {
    Name = "wordpress-redis"
    Environment = "test"
  }
}

# ---- IAM User for Reviewer ----
resource "aws_iam_user" "review_user" { 
  name = "reviewer"
}

resource "aws_iam_user_login_profile" "review_user_console" {
  user                    = aws_iam_user.review_user.name
  #password                = "Readonly123!"           
  password_reset_required = true                
}

resource "aws_iam_policy" "limited_read" {
  name        = "limited-read-only"
  path        = "/"
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

resource "aws_iam_access_key" "review_user_key" {
  user = aws_iam_user.review_user.name
}

data "aws_caller_identity" "current" {}
# output "reviewer_iam_username" {
#   value = aws_iam_user.review_user.name
# }

# output "reviewer_iam_access_key_id" {
#   value = aws_iam_access_key.review_user_key.id
# }

# output "reviewer_iam_secret_access_key" {
#   value     = aws_iam_access_key.review_user_key.secret
#   sensitive = true
# }

output "wordpress_public_ip" {
  description = "Public IP of the WordPress EC2 instance"
  value       = aws_instance.wordpress.public_ip
}

output "wordpress_readonly_user" {
  value       = "reviewer"
  description = "Read-only WordPress user"
}

output "wordpress_readonly_password" {
  value       = "readonly123"
  description = "Password for the read-only WordPress user"
}

output "wordpress_login_url" {
  value       = "http://${aws_instance.wordpress.public_ip}/wp-login.php"
  description = "Login URL for WordPress site"
}

output "reviewer_console_url" {
  value = "https://${data.aws_caller_identity.current.account_id}.signin.aws.amazon.com/console"
}

output "reviewer_iam_username" {
  value = aws_iam_user.review_user.name
}

output "reviewer_iam_console_password" {
  value     = aws_iam_user_login_profile.review_user_console.password
  sensitive = true
}

output "reviewer_iam_access_key_id" {
  value = aws_iam_access_key.review_user_key.id
}

output "reviewer_iam_secret_access_key" {
  value     = aws_iam_access_key.review_user_key.secret
  sensitive = true
}