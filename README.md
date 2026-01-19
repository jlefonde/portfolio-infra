# Portfolio Infrastructure 🏗️

This repository contains the Terraform-based Infrastructure as Code (IaC) for the Portfolio project's AWS infrastructure.

## 🔗 Part of Portfolio Ecosystem

This is one component of a distributed cloud architecture. For the complete project overview, architecture diagrams, and documentation, please visit:

👉 **[Portfolio - Main Repository](https://github.com/jlefonde/portfolio)**

## 📦 What's in this repo

* **Terraform configurations** for AWS resources (CloudFront, API Gateway, Lambda, S3, IAM, etc.)
* **Multi-environment setup** (Development & Production)
* **State management** via S3 backend with native locking
* **CI/CD workflows** for automated infrastructure deployment

## 🚀 Key Technologies

* Terraform
* AWS (CloudFront, API Gateway, Lambda, S3, Route53, IAM, SSM Parameter Store, Secrets Manager)
* GitHub Actions (OIDC authentication)

## 📚 Related Repositories

* [portfolio-backend](https://github.com/jlefonde/portfolio-backend) - Go Lambda functions and API logic
* [portfolio-frontend](https://github.com/jlefonde/portfolio-frontend) - Vue.js frontend application

---

For detailed setup instructions, architecture details, and deployment workflows, refer to the [main Portfolio repository](https://github.com/jlefonde/portfolio).
