# abz-devops-assessment
WP app deployment project from abz-agency
# DevOps Test Assignment – ABZ Agency

This project sets up a WordPress stack on AWS using Terraform.

## 🔧 Infrastructure Components

 - VPC: Custom VPC with public and private subnets across two availability zones (eu-west-1)
 - EC2: WordPress application server in a public subnet for internet access
 - RDS: MySQL database in a private subnet (not internet-accessible)
 - ElastiCache: Redis instance in a private subnet for session caching (not internet-accessible)
 - Security Groups: Properly isolated network access controls
 - NAT Gateway: Enables outbound internet access for private resources
 - IAM reviewer user with read-only access

## 🚀 How to Deploy

1. Clone the Repository
   git clone https://github.com/PawelHejlig/abz-devops-assessment-public

2. Configure AWS Access
   aws configure --profile tf-user

3. Apply Terraform

   terraform init
   terraform plan
   terraform apply

4. After Apply

Terraform will output:
 - WordPress public IP and login URL
 - IAM reviewer credentials
 - WordPress read-only user credentials

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
Access Key ID: <output from Terraform> (will send via email)
Secret Access Key: <output from Terraform> (will send via email)

## 📂 Project Structure

.
├── main.tf                # Core Terraform infrastructure
├── outputs.tf             # Exposes useful outputs
├── variables.tf           # (optional) Input variables
├── wordpress-setup.sh     # EC2 user data script to install WordPress
├── .gitignore             # Ignores sensitive files and state
└── README.md              # This file

## ⏱ Time Spent

I spent approximately 30 hours on this assignment (20 of 30 hours was debugging)

## ⚠️ Challenges Faced

Wordpress 


---
Thanks for the opportunity!

