# Deploying NutriAI to Azure Kubernetes Service (AKS) with AGIC

This guide walks you through building the containers, pushing them to Azure Container Registry (ACR), and deploying the microservices to an AKS cluster using the Application Gateway Ingress Controller (AGIC) for routing.

---

## Prerequisites

Before starting, ensure you have:
1. **Azure CLI** (`az`) installed and authenticated.
2. **Kubernetes CLI** (`kubectl`) installed.
3. An active **AKS Cluster** with the **AGIC Addon** enabled.
4. An active **Azure Container Registry (ACR)**.

---

## Step 1: Connect to AKS Cluster

Log in to Azure and fetch the credentials for your AKS cluster:

```bash
# Log in to Azure
az login

# Set your active subscription
az account set --subscription "<your-subscription-id-or-name>"

# Get AKS credentials (replaces or merges with ~/.kube/config)
az aks get-credentials --resource-group <your-resource-group> --name <your-aks-cluster-name>

# Verify connection
kubectl get nodes
```

---

## Step 2: Integrate ACR with AKS

If not already integrated, attach your ACR to the AKS cluster so the cluster has permissions to pull the images:

```bash
az aks update --name <your-aks-cluster-name> --resource-group <your-resource-group> --attach-acr <your-acr-name>
```

---

## Step 3: Build and Push Docker Images

The `docker-compose.yml` uses the `${REGISTRY}` environment variable to tag images. Build and push the images using your ACR login server name (e.g. `nutriaiacr.azurecr.io`).

```bash
# Set your ACR Registry login server variable (in PowerShell/Bash)
# Bash:
export REGISTRY="<your-acr-name>.azurecr.io"
# PowerShell:
$env:REGISTRY="<your-acr-name>.azurecr.io"

# 1. Build all services
docker compose build

# 2. Log in to your ACR
az acr login --name <your-acr-name>

# 3. Push all images to ACR
docker compose push
```

> [!NOTE]
> If your K8s manifests still use the default `nutriai_acr/` prefix, you can either update the image tags in the YAML files to match your ACR registry URL, or tag/push the images to `nutriai_acr` if you are using a local registry.
> For production, edit the `image:` fields in the manifest files (e.g. `manifests/gateway.yaml`, etc.) to point to your ACR login server: `<your-acr-name>.azurecr.io/<service-name>:latest`.

---

## Step 4: Configure Secrets & ConfigMaps

1. **Namespace**:
   Create the dedicated namespace first:
   ```bash
   kubectl apply -f manifests/namespace.yaml
   ```

2. **Secrets**:
   Prepare your database, JWT keys, and Azure service credentials. Base64-encode each sensitive value:
   ```bash
   # Linux/macOS:
   echo -n "actual-secret-value" | base64
   # Windows (PowerShell):
   [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("actual-secret-value"))
   ```
   Open `manifests/secrets.yaml`, replace all `<base64-encoded-value>` placeholders with the resulting strings, and apply:
   ```bash
   kubectl apply -f manifests/secrets.yaml
   ```

3. **ConfigMaps**:
   Update `manifests/configmap.yaml` with non-sensitive configurations (like endpoints, deployment names, and URLs), then apply:
   ```bash
   kubectl apply -f manifests/configmap.yaml
   ```

---

## Step 5: Deploy Services

Apply all microservice manifests in the proper dependency order:

```bash
# 1. Deploy Core Microservices
kubectl apply -f manifests/identity-service.yaml
kubectl apply -f manifests/ocr-service.yaml
kubectl apply -f manifests/nutrition-service.yaml
kubectl apply -f manifests/vitals-service.yaml
kubectl apply -f manifests/patient-service.yaml
kubectl apply -f manifests/admin-service.yaml
kubectl apply -f manifests/email-service.yaml

# 2. Deploy API Gateway (handles internal microservice reverse proxying)
kubectl apply -f manifests/gateway.yaml

# 3. Deploy Frontend (Web application client)
kubectl apply -f manifests/frontend.yaml
```

---

## Step 6: Deploy Ingress (AGIC)

Deploy the standard Kubernetes `Ingress` resource. This automatically configures routing paths on your Azure Application Gateway.

```bash
# Configure SSL certificates if needed (create tls secret)
# kubectl create secret tls nutriai-tls --cert=path/to/cert.pem --key=path/to/key.pem -n nutriai

kubectl apply -f manifests/ingress.yaml
```

---

## Step 7: Verification and Troubleshooting

Check the status of your deployments and pods:

```bash
# List all pods in the nutriai namespace
kubectl get pods -n nutriai

# Follow logs of a specific pod if it fails to start
kubectl logs -n nutriai deployment/gateway

# Describe the ingress to verify AGIC is binding correctly
kubectl describe ingress nutriai-ingress -n nutriai
```

### Fetch public IP
Once AGIC has provisioned the Application Gateway routing rules, get the public IP address:

```bash
kubectl get ingress nutriai-ingress -n nutriai
```
Use the printed IP address/hostname to test the routing.
- Path `/` routes to the **Frontend** client.
- Paths `/api` and `/admin` route to the **Gateway** microservice.

---

## Later Steps: Migrating All Configurations to Azure Key Vault (Option B: Service-Specific Isolation)

To implement maximum security isolation (Option B), every microservice will only have access to its own specific subset of secrets and configurations. Instead of using a single global secret pool, you will create **service-specific `SecretProviderClass` resources** that sync only the relevant keys from your Azure Key Vault into individual Kubernetes secrets.

---

### 1. Key Vault Secrets Layout

Configure the following secrets in your Azure Key Vault. (Note: Key Vault secret names only allow alphanumeric characters and dashes, so convert underscores `_` to dashes `-`).

| Config Group | Key Vault Secret Name | Maps to Env Var | Used By Services |
| :--- | :--- | :--- | :--- |
| **Shared / DB** | `database-url` | `DATABASE_URL` | All backend services |
| **Auth / Identity**| `jwt-secret-key` | `JWT_SECRET_KEY` | `gateway`, `identity-service` |
| | `entra-client-id` | `ENTRA_CLIENT_ID` | `identity-service` |
| | `entra-client-secret` | `ENTRA_CLIENT_SECRET` | `identity-service` |
| | `entra-tenant-id` | `ENTRA_TENANT_ID` | `identity-service` |
| **OCR / Storage** | `azure-storage-connection-string` | `AZURE_STORAGE_CONNECTION_STRING` | `ocr-service` |
| | `azure-storage-container-name` | `AZURE_STORAGE_CONTAINER_NAME` | `ocr-service` |
| | `azure-document-intelligence-endpoint`| `AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT` | `ocr-service` |
| | `azure-document-intelligence-key` | `AZURE_DOCUMENT_INTELLIGENCE_KEY` | `ocr-service` |
| **Nutrition / AI** | `azure-openai-endpoint` | `AZURE_OPENAI_ENDPOINT` | `nutrition-service` |
| | `azure-openai-key` | `AZURE_OPENAI_KEY` | `nutrition-service` |
| | `azure-openai-deployment-name` | `AZURE_OPENAI_DEPLOYMENT_NAME` | `nutrition-service` |
| | `azure-openai-api-version` | `AZURE_OPENAI_API_VERSION` | `nutrition-service` |
| | `azure-service-bus-connection-string`| `AZURE_SERVICE_BUS_CONNECTION_STRING` | `nutrition-service`, `email-service` |
| | `azure-service-bus-topic-name` | `AZURE_SERVICE_BUS_TOPIC_NAME` | `nutrition-service`, `email-service` |
| **Email / SMTP** | `azure-service-bus-subscription-name`| `AZURE_SERVICE_BUS_SUBSCRIPTION_NAME`| `email-service` |
| | `smtp-host` | `SMTP_HOST` | `email-service` |
| | `smtp-port` | `SMTP_PORT` | `email-service` |
| | `smtp-from-email` | `SMTP_FROM_EMAIL` | `email-service` |
| | `smtp-username` | `SMTP_USERNAME` | `email-service` |
| | `smtp-password` | `SMTP_PASSWORD` | `email-service` |
| | `app-url` | `APP_URL` | `email-service` |
| **Internal URLs** | `auth-service-url` | `AUTH_SERVICE_URL` | `gateway` |
| | `document-service-url` | `DOCUMENT_SERVICE_URL` | `gateway` |
| | `diet-service-url` | `DIET_SERVICE_URL` | `gateway` |
| | `health-service-url` | `HEALTH_SERVICE_URL` | `gateway` |
| | `notification-service-url` | `NOTIFICATION_SERVICE_URL` | `gateway` |
| | `profile-service-url` | `PROFILE_SERVICE_URL` | `gateway` |
| | `admin-service-url` | `ADMIN_SERVICE_URL` | `gateway` |
| **Frontend** | `backend-url` | `BACKEND_URL` | `frontend` |

---

### 2. Files to Add & Modify in the `manifests/` Folder

You will replace the static `secrets.yaml` and `configmap.yaml` files with service-specific `SecretProviderClass` manifests, and update each deployment to use them.

#### A. [NEW] Add Service-Specific `SecretProviderClass` Manifests

Define a separate provider class for each service. Below are examples for **Identity Service** and **API Gateway** microservices.

##### 1. Identity Service: `manifests/identity-kv-provider.yaml`
This provider only maps the secrets needed for login and Entra authentication.

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: identity-kv-provider
  namespace: nutriai
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"
    userAssignedIdentityID: "<your-managed-identity-client-id>"
    keyvaultName: "<your-keyvault-name>"
    tenantId: "<your-azure-tenant-id>"
    objects: |
      array:
        - |
          objectName: database-url
          objectType: secret
          alias: DATABASE_URL
        - |
          objectName: jwt-secret-key
          objectType: secret
          alias: JWT_SECRET_KEY
        - |
          objectName: entra-client-id
          objectType: secret
          alias: ENTRA_CLIENT_ID
        - |
          objectName: entra-client-secret
          objectType: secret
          alias: ENTRA_CLIENT_SECRET
        - |
          objectName: entra-tenant-id
          objectType: secret
          alias: ENTRA_TENANT_ID
  secretObjects:
    - secretName: identity-secrets
      type: Opaque
      data:
        - objectName: DATABASE_URL
          key: DATABASE_URL
        - objectName: JWT_SECRET_KEY
          key: JWT_SECRET_KEY
        - objectName: ENTRA_CLIENT_ID
          key: ENTRA_CLIENT_ID
        - objectName: ENTRA_CLIENT_SECRET
          key: ENTRA_CLIENT_SECRET
        - objectName: ENTRA_TENANT_ID
          key: ENTRA_TENANT_ID
```

##### 2. API Gateway: `manifests/gateway-kv-provider.yaml`
This provider only maps database, JWT, and routing destination configurations.

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: gateway-kv-provider
  namespace: nutriai
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"
    userAssignedIdentityID: "<your-managed-identity-client-id>"
    keyvaultName: "<your-keyvault-name>"
    tenantId: "<your-azure-tenant-id>"
    objects: |
      array:
        - |
          objectName: database-url
          objectType: secret
          alias: DATABASE_URL
        - |
          objectName: jwt-secret-key
          objectType: secret
          alias: JWT_SECRET_KEY
        - |
          objectName: auth-service-url
          objectType: secret
          alias: AUTH_SERVICE_URL
        - |
          objectName: document-service-url
          objectType: secret
          alias: DOCUMENT_SERVICE_URL
        - |
          objectName: diet-service-url
          objectType: secret
          alias: DIET_SERVICE_URL
        - |
          objectName: health-service-url
          objectType: secret
          alias: HEALTH_SERVICE_URL
        - |
          objectName: notification-service-url
          objectType: secret
          alias: NOTIFICATION_SERVICE_URL
        - |
          objectName: profile-service-url
          objectType: secret
          alias: PROFILE_SERVICE_URL
        - |
          objectName: admin-service-url
          objectType: secret
          alias: ADMIN_SERVICE_URL
  secretObjects:
    - secretName: gateway-secrets
      type: Opaque
      data:
        - objectName: DATABASE_URL
          key: DATABASE_URL
        - objectName: JWT_SECRET_KEY
          key: JWT_SECRET_KEY
        - objectName: AUTH_SERVICE_URL
          key: AUTH_SERVICE_URL
        - objectName: DOCUMENT_SERVICE_URL
          key: DOCUMENT_SERVICE_URL
        - objectName: DIET_SERVICE_URL
          key: DIET_SERVICE_URL
        - objectName: HEALTH_SERVICE_URL
          key: HEALTH_SERVICE_URL
        - objectName: NOTIFICATION_SERVICE_URL
          key: NOTIFICATION_SERVICE_URL
        - objectName: PROFILE_SERVICE_URL
          key: PROFILE_SERVICE_URL
        - objectName: ADMIN_SERVICE_URL
          key: ADMIN_SERVICE_URL
```

*(Create similar yaml files for: `ocr-kv-provider`, `nutrition-kv-provider`, `email-kv-provider`, `vitals-kv-provider`, `patient-kv-provider`, `admin-kv-provider`, and `frontend-kv-provider` matching the key list in Section 1).*

#### B. [DELETE] `manifests/secrets.yaml` and `manifests/configmap.yaml`
Once your service-specific provider classes are in place, delete these static shared files.

#### C. [MODIFY] Update Deployments to Mount and Consume Isolated Secrets

Since environment variables are now synced into dynamic, isolated secrets (e.g. `identity-secrets` for identity service, `gateway-secrets` for gateway), you can update the Deployment manifests to load all variables directly using `envFrom` pointing to their service-specific secret.

##### Example modification for `manifests/identity-service.yaml`:
```yaml
spec:
  template:
    spec:
      containers:
        - name: identity-service
          image: nutriai_acr/identity-service:latest
          # Load only this service's dynamic Key Vault secrets/configs
          envFrom:
            - secretRef:
                name: identity-secrets
          volumeMounts:
            - name: secrets-store-inline
              mountPath: "/mnt/secrets"
              readOnly: true
      volumes:
        - name: secrets-store-inline
          csi:
            driver: secrets-store.csi.k8s.io
            readOnly: true
            volumeAttributes:
              secretProviderClass: "identity-kv-provider"
```

##### Example modification for `manifests/gateway.yaml`:
```yaml
spec:
  template:
    spec:
      containers:
        - name: gateway
          image: nutriai_acr/gateway:latest
          # Load only this service's dynamic Key Vault secrets/configs
          envFrom:
            - secretRef:
                name: gateway-secrets
          volumeMounts:
            - name: secrets-store-inline
              mountPath: "/mnt/secrets"
              readOnly: true
      volumes:
        - name: secrets-store-inline
          csi:
            driver: secrets-store.csi.k8s.io
            readOnly: true
            volumeAttributes:
              secretProviderClass: "gateway-kv-provider"
```

By switching to `envFrom` and binding distinct `SecretProviderClass` resources to each service, you ensure strict access segregation: `ocr-service` container will only have the OCR credentials in its process environment, while `identity-service` container will only have login/identity credentials.

