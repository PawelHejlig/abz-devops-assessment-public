# abz-devops-assessment
AWS project from abz-agency
# DevOps Test Assignment – ABZ Agency

This project sets up a WordPress stack on AWS using Terraform.

## 🔧 Infrastructure Components

- VPC with public and private subnets
- EC2 instance running WordPress
- RDS (MySQL) as the WordPress database (private)
- ElastiCache (Redis) for session storage (private)
- IAM reviewer user with read-only access

## 🚀 How to Deploy

1. Clone the Repository

   git clone https://github.com/PawelHejlig/abz-devops-assessment-public

2. Configure AWS Access


3. Apply Terraform

   terraform init
   terraform apply

4. After Apply

Terraform will output:
- WordPress EC2 instance public IP (access via browser)
- IAM reviewer and WP read-only users login link and creds

## 📄 WordPress Access

- With credentials read-only user

## 🛠️ Configuration Notes

- Environment variables for DB and Redis are injected via EC2 user data.
- EC2 runs in a public subnet with HTTP/SSH allowed.
- RDS and Redis are in private subnets.
- Terraform handles the infrastructure provisioning and basic app setup.

## 🔐 Security

- A dedicated IAM user is created for the reviewer.
- The IAM user is limited to:
  - ec2:Describe*
  - rds:Describe*
  - elasticache:Describe*
  - ec2:DescribeVpcs, Subnets, and SecurityGroups
- AWS IAM User Credentials:
Username: reviewer
Access Key ID: <output from Terraform>
Secret Access Key: <output from Terraform>

## 📂 Project Structure

.
├── main.tf                # Core Terraform infrastructure
├── outputs.tf             # Exposes useful outputs
├── variables.tf           # (optional) Input variables
├── wordpress-setup.sh     # EC2 user data script to install WordPress
├── .gitignore             # Ignores sensitive files and state
└── README.md              # This file

## ⏱ Time Spent

I spent approximately 8 hours on this assignment.

## ⚠️ Challenges Faced

Wordpress :)

Thanks for the opportunity!

