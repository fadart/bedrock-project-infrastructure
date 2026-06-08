# Project Bedrock — InnovateMart EKS Infrastructure


This repository contains the infrastructure-as-code and application deployment configuration for InnovateMart's production-grade Kubernetes environment on AWS EKS. The project provisions a secure, observable, and automated cloud infrastructure for the Retail Store Sample Application.

Key capabilities:

- **Infrastructure as Code** — all AWS resources provisioned via Terraform with remote state
- **Managed databases** — RDS MySQL, RDS PostgreSQL, and DynamoDB replace in-cluster databases
- **Secure secrets** — database credentials stored in AWS SSM Parameter Store, never hardcoded
- **Observability** — CloudWatch Observability EKS add-on with FluentBit for container and control plane logs
- **Serverless** — S3 event notifications trigger a Lambda function that logs to CloudWatch
- **HTTPS** — TLS terminated at the ALB using an ACM certificate on a custom domain
- **CI/CD** — GitHub Actions automates `terraform plan` on PRs and `terraform apply` on merge


---

## Architecture

- **Networking:** A custom VPC (`project-bedrock-vpc`) with 2 public and 2 private subnets across `us-east-1a` and `us-east-1b`. A NAT Gateway in the public subnet allows private subnet resources to reach the internet.
- **Compute:** An EKS cluster (`project-bedrock-cluster`, Kubernetes 1.34) with a managed node group of 2x `t3.medium` EC2 instances in private subnets.
- **Data layer:** RDS MySQL and RDS PostgreSQL instances in private subnets. DynamoDB table for the carts service. All databases are inaccessible from the public internet.
- **Ingress:** AWS Load Balancer Controller provisions an internet-facing ALB that routes traffic to the UI service.
- **Serverless:** A private S3 bucket (`bedrock-assets-alt-soe-025-3604`) triggers a Lambda function (`bedrock-asset-processor`) on file upload. The Lambda logs the filename to CloudWatch.
- **Observability:** CloudWatch Observability EKS add-on with FluentBit ships container and control plane logs to CloudWatch.
- **Security:** IAM user `bedrock-dev-view` has console read-only access and Kubernetes RBAC view access scoped to the `retail-app` namespace.


<img width="2522" height="2282" alt="image" src="https://github.com/user-attachments/assets/ceb7d73a-91c4-4ce1-8b0f-b5a863f1410b" />

---

## Repository structure
.
├── .github/
│   └── workflows/
│       └── terraform.yml        # CI/CD pipeline
├── helm/
│   └── retail-store/            # Helm chart for app deployment
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
├── kubernetes/
│   ├── db-secrets.yaml          # Database credentials as K8s secrets
│   ├── rbac.yaml                # RBAC for bedrock-dev-view
│   ├── ingress.yaml             # ALB ingress resource
│   └── namespace.yaml
├── lambda/
│   └── index.py                 # Lambda function code
├── terraform/
│   ├── modules/
│   │   ├── vpc/                 # VPC, subnets, NAT gateway
│   │   ├── eks/                 # EKS cluster and node group
│   │   ├── rds/                 # RDS MySQL and PostgreSQL
│   │   ├── dynamodb/            # DynamoDB table
│   │   ├── iam/                 # bedrock-dev-view IAM user
│   │   └── s3-lambda/           # S3 bucket and Lambda function
│   └── root/                    # Terraform entry point
│       ├── backend.tf
│       ├── main.tf
│       ├── outputs.tf
│       ├── providers.tf
│       ├── variables.tf
│       └── versions.tf
└── grading.json                 # Terraform outputs for grading script
---

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- kubectl
- helm
- eksctl

---

## Deployment guide

### Step 1 — Bootstrap remote state

The Terraform state is stored remotely in S3. This bucket must exist before running Terraform:

```bash
aws s3api create-bucket \
  --bucket bedrock-terraform-state-035786426828 \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket bedrock-terraform-state-035786426828 \
  --versioning-configuration Status=Enabled
```

### Step 2 — Provision infrastructure

```bash
cd terraform/root
terraform init
terraform apply
```

This provisions the VPC, EKS cluster, RDS instances, DynamoDB, S3 bucket, Lambda function, and IAM user.

### Step 3 — Connect kubectl to the cluster

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name project-bedrock-cluster
```

### Step 4 — Install AWS Load Balancer Controller

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

eksctl create iamserviceaccount \
  --cluster=project-bedrock-cluster \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::035786426828:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve \
  --region us-east-1

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=project-bedrock-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=us-east-1 \
  --set vpcId=vpc-0b6dc0205dd7068d0
```

### Step 5 — Deploy the application

```bash
kubectl apply -f kubernetes/db-secrets.yaml

helm upgrade --install retail-store helm/retail-store-upstream \
  --namespace retail-app \
  --create-namespace \
  --values helm/retail-store-upstream/values.yaml
```

---

## Helm deployment (bonus)

The retail store application is packaged as a Helm chart located at `helm/retail-store-upstream/`.

Deploy with a single command:

```bash
helm upgrade --install retail-store helm/retail-store-upstream \
  --namespace retail-app \
  --create-namespace \
  --values helm/retail-store-upstream/values.yaml
```

### Chart structure
helm/retail-store-upstream/
├── Chart.yaml
├── values.yaml
└── templates/
├── deployment.yaml     # Namespace
├── catalog.yaml        # Catalog service + ExternalName DB service
├── ui.yaml             # UI service
├── carts.yaml          # Carts service
├── orders.yaml         # Orders service
├── checkout.yaml       # Checkout service
├── assets.yaml         # Assets service
├── db-services.yaml    # ExternalName services for RDS
└── ingress.yaml        # ALB ingress
Override database endpoints or other settings by editing `helm/retail-store-upstream/values.yaml`.

---

## CI/CD pipeline

The GitHub Actions pipeline automates all infrastructure changes.

| Trigger | Action |
|---|---|
| Pull Request opened against `main` | Runs `terraform plan` and posts output as a PR comment |
| Pull Request merged to `main` | Runs `terraform apply` automatically |

### How to trigger

1. Create a feature branch and make changes to Terraform files
2. Open a Pull Request against `main`
3. Review the plan output posted as a PR comment
4. Merge the PR to apply changes


**Pipeline URL:** https://github.com/fadart/bedrock-project-infrastructure/actions

AWS credentials are stored as GitHub Actions repository secrets and never hardcoded in workflow files.

---

## Application

**URL:** `https://bedrock.fatimahonomoh.com`

| Service | Description |
|---|---|
| ui | Store frontend |
| catalog | Product catalog — connects to RDS MySQL |
| orders | Order management — connects to RDS PostgreSQL |
| carts | Shopping cart — connects to DynamoDB |
| checkout | Checkout orchestration |
| assets | Static assets |

---

## Observability

- **Control plane logs:** API, Audit, Authenticator, ControllerManager, Scheduler — shipped to CloudWatch
- **Container logs:** Shipped via FluentBit to CloudWatch log groups
- **Add-on:** Amazon CloudWatch Observability EKS add-on `v6.2.0`

---

## Serverless

- **S3 bucket:** `bedrock-assets-alt-soe-025-3604` — private, public access blocked
- **Lambda function:** `bedrock-asset-processor` — Python 3.11
- **Trigger:** Any file uploaded to the S3 bucket invokes the Lambda
- **Logic:** Lambda logs `Image received: [filename]` to CloudWatch

---

## Security

| Resource | Configuration |
|---|---|
| `bedrock-dev-view` IAM user | `ReadOnlyAccess` managed policy |
| `bedrock-dev-view` S3 access | `s3:PutObject` on assets bucket only |
| `bedrock-dev-view` K8s access | `view` ClusterRole in `retail-app` namespace |
| RDS instances | Private subnets, EKS nodes access only |
| Database credentials | Kubernetes secrets, never hardcoded |

---

## Advanced networking & ingress

The application is exposed securely over HTTPS using a custom domain and ACM certificate.

- **Custom domain:** `bedrock.fatimahonomoh.com`
- **ACM certificate:** `arn:aws:acm:us-east-1:035786426828:certificate/091de43b-383c-44b2-99ff-901aecbff237`
- **TLS termination:** At the ALB on port 443
- **HTTP redirect:** All HTTP traffic redirects to HTTPS automatically

**Application URL:** `https://bedrock.fatimahonomoh.com`
