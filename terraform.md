# NutriAI Health Portal — Terraform Deployment Guide

## Overview

This guide covers everything you need to deploy the NutriAI infrastructure on Azure using Terraform — what to fill in your `.tfvars`, what Azure resources must exist beforehand, and the exact step-by-step commands.

---

## Part 1: Prerequisites — What Must Exist Before Running Terraform

These resources must be **manually created once** before Terraform can run. Terraform uses them but does not create them.

### 1. Azure Subscription
- An active Azure subscription with sufficient quota
- Your account must have **Owner** or **Contributor + User Access Administrator** role on the subscription

### 2. Azure CLI Installed & Logged In
```bash
# Install Azure CLI (if not already)
# https://learn.microsoft.com/en-us/cli/azure/install-azure-cli

# Log in
az login

# Set your subscription
az account set --subscription "<your-subscription-id>"

# Verify
az account show
```

### 3. Terraform Installed (≥ 1.5.0)
```bash
# Download from https://developer.hashicorp.com/terraform/downloads
terraform -version
```

### 4. Terraform Remote State — Storage Account
Terraform stores its state in Azure Blob Storage. Create this **once** before the first `terraform init`:

```bash
# Create resource group for state
az group create \
  --name nutriai-terraform-state \
  --location eastus

# Create storage account (name must be globally unique)
az storage account create \
  --name nutriaitfstate \
  --resource-group nutriai-terraform-state \
  --location eastus \
  --sku Standard_LRS \
  --kind StorageV2

# Create blob container
az storage container create \
  --name tfstate \
  --account-name nutriaitfstate
```

> [!IMPORTANT]
> The names `nutriai-terraform-state`, `nutriaitfstate`, and `tfstate` must exactly match what is in `main.tf` backend block. If you change them, update `main.tf` too.

### 5. Azure Document Intelligence Resource
Terraform does not provision Document Intelligence (it requires manual region approval). Create it manually:

```bash
az cognitiveservices account create \
  --name nutriai-doc-intelligence \
  --resource-group nutriai-terraform-state \
  --kind FormRecognizer \
  --sku S0 \
  --location eastus \
  --yes

# Get the endpoint and key
az cognitiveservices account show \
  --name nutriai-doc-intelligence \
  --resource-group nutriai-terraform-state \
  --query properties.endpoint

az cognitiveservices account keys list \
  --name nutriai-doc-intelligence \
  --resource-group nutriai-terraform-state
```

Save the **endpoint** and **key1** — you'll need them in your `.tfvars`.

### 6. Microsoft Entra ID App Registration (optional for SSO)
If you want Microsoft SSO login:

```bash
# Create app registration
az ad app create --display-name "NutriAI Health Portal"

# Note the appId (client_id) and tenantId from the output
```

Then create a client secret in the Azure Portal under **App registrations → Certificates & secrets**.

---

## Part 2: What Goes in `.tfvars`

Copy `terraform.tfvars.example` to `terraform.tfvars` and fill in the values below.

### Required Variables

| Variable | Required | Where to get it |
|----------|----------|-----------------|
| `environment` | ✅ | `"dev"` or `"prod"` |
| `document_intelligence_endpoint` | ✅ | Step 5 above |
| `document_intelligence_key` | ✅ | Step 5 above |

### Optional Variables (have safe defaults)

| Variable | Default | Notes |
|----------|---------|-------|
| `project_name` | `"nutriai"` | Prefix for all resource names |
| `location` | `"eastus"` | Azure region |
| `entra_client_id` | `""` | Leave blank to skip SSO |
| `entra_client_secret` | `""` | Leave blank to skip SSO |
| `entra_tenant_id` | `""` | Leave blank to skip SSO |
| `openai_model_deployment` | `"gpt-4"` | Must match your OpenAI deployment name |
| `smtp_host` | `"smtp.gmail.com"` | Email server |
| `smtp_port` | `587` | Email port |
| `smtp_username` | `""` | Email address |
| `smtp_password` | `""` | App password (not your Gmail password) |
| `app_service_sku` | `"B2"` | Override in `environments/*.tfvars` |
| `postgres_sku` | `"B_Standard_B1ms"` | Override in `environments/*.tfvars` |
| `appgw_sku_name` | `"Standard_v2"` | Do not change — min for path routing |
| `appgw_sku_tier` | `"Standard_v2"` | Do not change |
| `appgw_capacity` | `2` | Override in `environments/*.tfvars` |

### Example `terraform.tfvars`

```hcl
environment = "dev"
location    = "eastus"

# Azure Document Intelligence (from Step 5)
document_intelligence_endpoint = "https://nutriai-doc-intelligence.cognitiveservices.azure.com/"
document_intelligence_key      = "abc123..."

# Microsoft Entra ID (from Step 6, or leave blank)
entra_client_id     = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
entra_client_secret = "your-client-secret"
entra_tenant_id     = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Email (optional)
smtp_username = "your@gmail.com"
smtp_password = "your-app-password"
```

> [!NOTE]
> **Secrets (database password, JWT key, connection strings)** are auto-generated by Terraform using `random_password` and stored directly in Key Vault. You do NOT need to provide them in `.tfvars`.

---

## Part 3: Step-by-Step Deployment

### Step 1 — Clone and navigate to the Terraform directory
```bash
cd cloud_project/terraform
```

### Step 2 — Initialize Terraform (connect to remote state)
```bash
terraform init
```
This downloads providers (`azurerm`, `azuread`, `random`) and connects to the Azure Blob Storage backend.

### Step 3 — Create workspaces
```bash
# Create dev workspace
terraform workspace new dev

# Create prod workspace
terraform workspace new prod

# List workspaces
terraform workspace list
```

### Step 4 — Select the workspace you want to deploy
```bash
# For dev
terraform workspace select dev

# For prod
terraform workspace select prod
```

### Step 5 — Copy and fill tfvars
```bash
# Copy example
cp terraform.tfvars.example terraform.tfvars

# Edit it with your values
# Fill in: document_intelligence_endpoint, document_intelligence_key
# Optionally: entra_*, smtp_*
```

### Step 6 — Validate configuration
```bash
terraform validate
```

### Step 7 — Preview what will be created (dry run)
```bash
# Dev
terraform plan -var-file=environments/dev.tfvars

# Prod
terraform plan -var-file=environments/prod.tfvars
```
Review the output — it should show **~65–70 resources to add**, zero to destroy.

### Step 8 — Apply (deploy to Azure)
```bash
# Dev
terraform apply -var-file=environments/dev.tfvars

# Prod
terraform apply -var-file=environments/prod.tfvars
```
Type `yes` when prompted. First deployment takes **15–25 minutes** (PostgreSQL takes the longest).

### Step 9 — Get output values
```bash
terraform output
```

Key outputs:
| Output | Description |
|--------|-------------|
| `application_gateway_ip` | Public IP — point your DNS here |
| `application_gateway_fqdn` | FQDN of the gateway |
| `backend_url` | Backend App Service hostname |
| `frontend_url` | Frontend App Service hostname |
| `container_registry_login_server` | ACR login server for Docker push |
| `key_vault_name` | Key Vault name |

---

## Part 4: Push Docker Images to ACR

After Terraform deploys, you need to push your container images so the App Services have something to run:

```bash
# Get ACR credentials
ACR_SERVER=$(terraform output -raw container_registry_login_server)

# Login to ACR
az acr login --name $(echo $ACR_SERVER | cut -d'.' -f1)

# Build and push backend
docker build -f Dockerfile.backend -t $ACR_SERVER/nutriai-backend:latest .
docker push $ACR_SERVER/nutriai-backend:latest

# Build and push frontend
docker build -f frontend/Dockerfile -t $ACR_SERVER/nutriai-frontend:latest ./frontend
docker push $ACR_SERVER/nutriai-frontend:latest
```

---

## Part 5: Destroy Infrastructure

```bash
# Select workspace first
terraform workspace select dev

# Destroy all resources in that workspace
terraform destroy -var-file=environments/dev.tfvars
```

> [!CAUTION]
> This deletes **all resources** including the database. Key Vault has soft-delete enabled (7 days) and purge protection — it cannot be force-deleted immediately.

---

## Part 6: Summary of Azure Resources Created by Terraform

| # | Resource | Azure Service |
|---|----------|---------------|
| 1 | Resource Group | Azure Resource Manager |
| 2 | Virtual Network + 5 Subnets | Azure VNet |
| 3 | Private DNS Zone (PostgreSQL) | Azure DNS |
| 4 | Container Registry (ACR) | Azure ACR |
| 5 | App Service Plan (Linux) | Azure App Service |
| 6 | Backend App Service (FastAPI) | Azure App Service |
| 7 | Frontend App Service (Nginx) | Azure App Service |
| 8 | Application Gateway | Azure Application Gateway |
| 9 | Public IP (for App Gateway) | Azure Network |
| 10 | PostgreSQL Flexible Server | Azure Database |
| 11 | PostgreSQL Database (`nutriai`) | Azure Database |
| 12 | Storage Account + Container | Azure Blob Storage |
| 13 | Azure OpenAI Account | Azure Cognitive Services |
| 14 | GPT-4 Deployment | Azure OpenAI |
| 15 | Service Bus Namespace | Azure Service Bus |
| 16 | Service Bus Topic + Subscription | Azure Service Bus |
| 17 | Key Vault | Azure Key Vault |
| 18 | 15 Key Vault Secrets | Azure Key Vault |
| 19 | Entra ID App Registration | Microsoft Entra ID |
| 20 | Entra ID Client Secret | Microsoft Entra ID |
| + | Random passwords (JWT, DB) | Terraform `random` |

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `Backend initialization required` | Run `terraform init` again |
| `Key Vault already exists` | Key Vault names are globally unique — change `project_name` |
| `Storage account name taken` | Change `nutriaitfstate` in both the CLI command and `main.tf` |
| `App Service can't read Key Vault secret` | Ensure managed identity is enabled and access policy was applied — run `terraform apply` again |
| `PostgreSQL connection timeout` | DB is inside VNet — connect only from within the App Service or via VPN |
| `Docker image not found` | Push your images to ACR first (Part 4) |
