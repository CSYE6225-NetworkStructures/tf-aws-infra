#  tf-aws-infra
**Terraform Infrastructure for AWS**  

This repository contains Terraform configuration to provision AWS infrastructure, including the **AWS VPC** and **AWS EC2** module. It uses **GitHub Actions for Continuous Integration (CI)** to check formatting and validate Terraform code.

---

## Repository Structure
```
tf-aws-infra/
│── AWS-VPC/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│── .github/workflows/
│   ├── terraform-ci.yml
│── README.md
```

---

## Prerequisites
Ensure you have the following installed before running Terraform:
- **Terraform CLI** ([Install Guide](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli))
- **AWS CLI** ([Install Guide](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html))
- **AWS Credentials** configured in `~/.aws/credentials`
- **Git** installed for version control

---

## Getting Started with Terraform
Follow these steps to run Terraform locally:

### 1️ Clone the Repository
```bash
git clone https://github.com/your-username/tf-aws-infra.git
cd tf-aws-infra/AWS-VPC
```

### 2️ Initialize Terraform
This downloads the required providers and initializes the workspace.
```bash
terraform init
```

### 3️ Format and Validate Terraform Code
Before applying changes, run:
```bash
terraform fmt -recursive
terraform validate
```

### 4️ Plan Terraform Execution
See what changes Terraform will make to AWS:
```bash
terraform plan
```

### 5️ Apply Changes
Apply the infrastructure changes to AWS:
```bash
terraform apply -auto-approve
```

### 6️ Destroy Infrastructure (If Needed)
To remove the created infrastructure:
```bash
terraform destroy -auto-approve
```

---

## GitHub Actions Workflow
This repository includes **GitHub Actions CI** to check Terraform code automatically.

### How It Works
- Runs on **every pull request to `main`**.
- Executes:
  - `terraform fmt -check -recursive` (ensures code formatting)
  - `terraform validate` (checks Terraform syntax)
- Prevents merging if checks fail.