# Local Verification and Testing Guide (Docker Compose)

This guide provides step-by-step instructions to validate the **NutriAI Health Portal** microservices application locally using `docker-compose.yml`. It details what external services are needed, how to configure your environment variables, and how to verify each feature through the application UI.

---

## Architecture Overview

The frontend React client acts as a single point of entry. It sends requests to `/api/*`, which the Nginx server in the frontend container forwards internally to the API Gateway. The API Gateway then routes requests to the respective microservices:

```
[Browser] ──> [Frontend Nginx (Port 3000)]
                      │
                      └──> (internal /api proxy) ──> [API Gateway (Port 8000)]
                                                            │
         ┌──────────────────┬───────────────────┬───────────┴───────────┬──────────────┐
         ▼                  ▼                   ▼                       ▼              ▼
[Identity (8001)]    [OCR (8002)]      [Nutrition (8003)]        [Vitals (8004)]   [Others...]
```

---

## Step 1: Provision Required Services (Azure Portal UI Steps)

To test the full capability of the application, you need to create the required Azure resources using the Azure Portal. Follow these step-by-step instructions for each service:

---

### 1. Azure Storage Account (Blob Storage)
**Required For:** Storing patient medical report PDFs/images.

1. Log in to the [Azure Portal](https://portal.azure.com).
2. In the search bar at the top, search for **Storage accounts** and select it.
3. Click **+ Create** to open the wizard.
4. Fill in the **Basics** tab:
   * **Subscription:** Select your active Azure subscription.
   * **Resource Group:** Click *Create new* and name it `nutriai-rg` (to group all resources).
   * **Storage account name:** Enter a unique lowercase name, e.g., `nutriaidocstorage` (alphanumeric only, 3-24 characters).
   * **Region:** Select your closest geographical region.
   * **Performance:** Select **Standard**.
   * **Redundancy:** Select **Locally-redundant storage (LRS)** (recommended to minimize development costs).
5. Click **Review + create** and then click **Create**.
6. Once deployment is complete, click **Go to resource**.
7. Under the **Data storage** section on the left-side panel, click on **Containers**.
8. Click **+ Container** at the top:
   * **Name:** Enter `nutriai-documents`.
   * **Public access level:** Leave as **Private (no anonymous access)**.
   * Click **Create**.
9. In the left panel, scroll down to the **Security + networking** section and click on **Access keys**.
10. Click **Show** next to **key1** and copy the **Connection string**. Add this connection string to your `.env` file as `AZURE_STORAGE_CONNECTION_STRING`.

---

### 2. Azure Document Intelligence (OCR Service)
**Required For:** Extracting heart rate, blood pressure, cholesterol, and other metrics from uploaded documents.

1. In the Azure Portal, click **Create a resource** (top-left button) or search for **Document Intelligence** in the search bar.
2. Click **Create** under the Document Intelligence resource.
3. Fill in the deployment details:
   * **Subscription:** Choose your active subscription.
   * **Resource Group:** Select your existing group `nutriai-rg`.
   * **Region:** Select the same region as your storage account.
   * **Name:** Enter a unique name, e.g., `nutriai-doc-ocr`.
   * **Pricing tier:** Select **Free F0** (if you have already deployed a free tier resource, select **Standard S0**).
4. Click **Review + create**, then **Create**.
5. Once deployed, click **Go to resource**.
6. Under **Resource Management** in the left panel, click on **Keys and Endpoint**.
7. Copy **Key 1** and paste it into `.env` as `AZURE_DOCUMENT_INTELLIGENCE_KEY`.
8. Copy the **Endpoint** URL and paste it into `.env` as `AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT`.

---

### 3. Azure OpenAI Service (AI Engine)
**Required For:** Processing medical summary stats and generating the personalized diet plans.

1. In the Azure Portal search bar, search for **Azure OpenAI** and select it.
2. Click **+ Create**.
3. Fill in the resource details:
   * **Subscription:** Select your subscription.
   * **Resource Group:** Select `nutriai-rg`.
   * **Region:** Select a region that supports the GPT-4 model (e.g., **East US** or **Sweden Central**).
   * **Name:** Enter a unique name, e.g., `nutriai-openai-service`.
   * **Pricing tier:** Select **Standard S0**.
4. Click **Next** until you reach **Review + submit**, then click **Create**.
5. Once deployed, go to the resource. Under **Resource Management** on the left menu, click **Keys and Endpoint**.
6. Copy **Key 1** to `.env` as `AZURE_OPENAI_KEY` and the **Endpoint** URL as `AZURE_OPENAI_ENDPOINT`.
7. Now, from the Overview page, click the button **Go to Azure OpenAI Studio** (or go to [https://oai.azure.com](https://oai.azure.com) in your browser).
8. In Azure OpenAI Studio, click on **Deployments** under the *Management* section on the left sidebar.
9. Click **+ Create new deployment**:
   * **Select a model:** Choose **gpt-4** (or `gpt-35-turbo` if GPT-4 is restricted in your region).
   * **Model version:** Select the default or auto-update choice.
   * **Deployment name:** Enter exactly `gpt-4`.
10. Click **Create**. This deployment name `gpt-4` must match the `AZURE_OPENAI_DEPLOYMENT_NAME` value in your `.env`.

---

### 4. Azure Service Bus
**Required For:** Decoupling the diet planner from the email reminder sender (asynchronously sending meal schedules).

1. In the Azure Portal, search for **Service Bus** and select it.
2. Click **+ Create**.
3. Fill in the namespace details:
   * **Subscription:** Choose your active subscription.
   * **Resource Group:** Select `nutriai-rg`.
   * **Namespace name:** Enter a unique lowercase name, e.g., `nutriai-sb-namespace`.
   * **Location:** Choose your preferred region.
   * **Pricing tier:** Select **Standard** (Crucial: *Basic* pricing tier does not support topics/subscriptions, which are required by the app).
4. Click **Review + create**, then click **Create**.
5. Once deployment completes, click **Go to resource**.
6. Under **Entities** in the left menu, click on **Topics**.
7. Click **+ Topic** at the top:
   * **Name:** Enter `meal-reminders`.
   * Leave default partition settings and click **Create**.
8. In the topics list, click on the newly created **`meal-reminders`** topic to open its configuration page.
9. Under **Entities** in the left menu *of the topic page*, click **Subscriptions**.
10. Click **+ Subscription** at the top:
    * **Name:** Enter `email-sender`.
    * **Max delivery count:** Leave as `10`.
    * Click **Create**.
11. Navigate back to the main Service Bus Namespace page (click on your namespace name in the breadcrumbs at the top).
12. Under **Settings** in the left panel, click on **Shared access policies**.
13. Click on the default policy named **`RootManageSharedAccessKey`** (or click *+ Add* to create a new policy with Send, Listen, and Manage permissions).
14. Copy the **Primary Connection String** (click the copy icon). Paste it into `.env` as `AZURE_SERVICE_BUS_CONNECTION_STRING`.

---

### 5. SMTP/SendGrid Account
**Required For:** Sending the registration confirmation and daily meal reminder emails.

1. **Option A (SMTP / Gmail):** 
   * Go to your Google Account Settings -> Security.
   * Enable **2-Step Verification**.
   * Go to **App Passwords**, generate a password for App: *Mail* and Device: *Other*.
   * Use `SMTP_HOST=smtp.gmail.com`, `SMTP_PORT=587`, `SMTP_USERNAME=<your-email>`, and the 16-character generated app password as `SMTP_PASSWORD`.
2. **Option B (SendGrid):**
   * Register a free account at SendGrid.
   * Go to **Settings** -> **API Keys** and create an API Key with full access.
   * Copy the API key and set it as `SENDGRID_API_KEY` (if you choose to use the SendGrid email provider integration).


---

## Step 2: Configure the `.env` File

Copy `.env.example` to `.env` in the root of the project:

```bash
cp .env.example .env
```

Open the `.env` file and populate the credentials retrieved from Step 1:

```env
# Database & Authentication
DATABASE_URL=postgresql://nutriai_user:nutriai_password@postgres:5432/nutriai
JWT_SECRET_KEY=super-secret-jwt-key-for-development
JWT_ALGORITHM=HS256
JWT_EXPIRY_MINUTES=1440

# Azure OpenAI
AZURE_OPENAI_ENDPOINT=https://your-openai-endpoint.openai.azure.com/
AZURE_OPENAI_KEY=your-openai-key-here
AZURE_OPENAI_DEPLOYMENT_NAME=gpt-4
AZURE_OPENAI_API_VERSION=2024-02-01

# Azure Storage
AZURE_STORAGE_CONNECTION_STRING=DefaultEndpointsProtocol=https;AccountName=...;AccountKey=...;EndpointSuffix=core.windows.net
AZURE_STORAGE_CONTAINER_NAME=nutriai-documents

# Azure Service Bus
AZURE_SERVICE_BUS_CONNECTION_STRING=Endpoint=sb://your-service-bus.servicebus.windows.net/;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=...
AZURE_SERVICE_BUS_TOPIC_NAME=meal-reminders
AZURE_SERVICE_BUS_SUBSCRIPTION_NAME=email-sender

# Azure Document Intelligence (OCR)
AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT=https://your-doc-intel-endpoint.cognitiveservices.azure.com/
AZURE_DOCUMENT_INTELLIGENCE_KEY=your-document-intelligence-key-here

# Email SMTP Setup (e.g. Gmail)
EMAIL_PROVIDER=smtp
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your-gmail-username@gmail.com
SMTP_PASSWORD=your-app-specific-password
SMTP_FROM_EMAIL=noreply@nutriai-health.com

# App URL
APP_URL=http://localhost:3000
```

---

## Step 3: Run the Application

Start the local multi-container development environment:

```bash
# Set registry namespace locally (defaults to nutriai_acr)
export REGISTRY=nutriai_acr

# Build and start services
docker compose up --build
```

Verify that all 11 containers (`postgres`, `redis`, `gateway`, `identity-service`, `ocr-service`, `nutrition-service`, `vitals-service`, `patient-service`, `admin-service`, `email-service`, and `frontend`) are up and healthy:

```bash
docker compose ps
```

---

## Step 4: Verify Features in the UI

Open your browser and navigate to **`http://localhost:3000`**. Test the following integration flows:

### 1. User Authentication (Login / Register Screen)
* **Under the Hood**: Browser calls `/api/auth` ──> `gateway` ──> `identity-service` ──> `postgres`.
* **Testing Step**:
  1. Click **Register** in the UI, fill in the credentials, and submit.
  2. Log in using the registered credentials.
  3. Ensure a login session is created and you are redirected to the user Dashboard.

### 2. Upload and Parse Medical Records (OCR Upload Section)
* **Under the Hood**: Browser calls `/api/documents/upload` ──> `gateway` ──> `ocr-service`. The service uploads the document to Azure Blob Storage and sends it to Azure Document Intelligence for OCR parsing.
* **Testing Step**:
  1. Go to the **Medical Documents** page in the UI.
  2. Upload a sample medical report PDF/Image (e.g., blood test report).
  3. Verify that the file successfully uploads, status changes to **Parsed**, and extracted lab metrics (such as heart rate, blood sugar, or cholesterol levels) display automatically in the dashboard.

### 3. Generate Personalized Diet Plan (Diet Planner Section)
* **Under the Hood**: Browser calls `/api/diet/generate` ──> `gateway` ──> `nutrition-service` ──> Azure OpenAI (`gpt-4` model).
* **Testing Step**:
  1. Go to the **Diet Planner** section.
  2. Input target health goals (e.g., "Reduce cholesterol, high protein") and dietary restrictions (e.g., "Vegetarian").
  3. Click **Generate Plan**.
  4. Verify that the AI-generated weekly plan successfully populates in the UI list.

### 4. Meal Reminder Emails (Service Bus + SMTP Relay)
* **Under the Hood**: 
  - `nutrition-service` publishes a meal schedule reminder to the Azure Service Bus topic `meal-reminders`.
  - `email-service` consumes the message from the subscription `email-sender` and triggers SMTP relay to mail out the reminder.
* **Testing Step**:
  1. Set a daily meal reminder time in the **Reminders** UI page.
  2. Wait for the scheduled window (or trigger a reminder event from the UI).
  3. Check the inbox of the email account used during registration to verify that the meal reminder email has been successfully delivered.

### 5. Health Vitals Logs (Dashboard Vitals Section)
* **Under the Hood**: Browser calls `/api/vitals` ──> `gateway` ──> `vitals-service`.
* **Testing Step**:
  1. Go to the **Vitals Log** page.
  2. Input measurements like Blood Pressure, Weight, and Blood Sugar.
  3. Submit and verify that the data charts on the dashboard update in real time.
