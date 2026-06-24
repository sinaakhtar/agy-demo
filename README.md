# Antigravity CLI Interactive Demo Platform

This project provides a serverless, highly secure, interactive sandbox environment designed to demonstrate the agentic software development capabilities of the **Antigravity CLI** (e.g., to a CTO or potential enterprise client).

Instead of a passive screen-share, the visitor gets a link to a live terminal preloaded with a demo project. A guided sidebar on the left provides one-click buttons that dynamically type commands into the terminal, demonstrating the agent's ability to understand code, diagnose bugs, fix them, and write new features.

---

## 🚀 Key Features & Architecture

*   **Real Interactive Terminal**: Renders a live terminal in the browser using `xterm.js`, connected via WebSockets to a real `bash` PTY running inside a Cloud Run container.
*   **Complete Session Isolation**: Configured with **Cloud Run Concurrency = 1**. Every user who opens the link is instantly allocated a dedicated, isolated container instance. There is no shared state, file leakage, or cross-talk between user sessions.
*   **Guided Walkthrough Sidebar**: Click-to-type macros simulate character-by-character keyboard input, giving a realistic "hands-on CLI" experience while keeping the demo structured and error-free.
*   **Transparent Enterprise Security**: Secured using Google Cloud **Identity-Aware Proxy (IAP)** to control access. The Antigravity CLI authenticates to Vertex AI (Gemini) securely using the container's IAM Service Account with Application Default Credentials (ADC)—no API keys are exposed or managed.

---

## 📁 Project Structure

```
agy-demo/
├── backend/
│   ├── package.json
│   └── server.js            # Node.js Express server handling WebSockets (node-pty)
├── frontend/
│   ├── index.html           # Split-pane UI layout
│   ├── style.css            # Slick dark IDE stylesheet
│   └── app.js               # Web UI controller & character typing engine
├── demo-repo/               # The Flask Todo App target codebase
│   ├── app.py               # Flask application (contains a delete-endpoint bug)
│   ├── test_app.py          # Pytest unit tests (delete test fails initially)
│   └── requirements.txt
├── terraform/               # Infrastructure as Code (IaC)
│   ├── main.tf              # Cloud Run service, service accounts, and IAM policies
│   ├── lb.tf                # HTTPS Load Balancer, Serverless NEG, SSL, and IAP setup
│   └── variables.tf
├── Dockerfile               # Multi-stage container (Python + Node.js + Antigravity CLI)
├── deploy.sh                # Main interactive deployment automation script
└── README.md
```

---

## 🛠️ Deployment Instructions

The entire platform is automated and can be deployed from your terminal in minutes.

### 📋 Prerequisites
1.  A Google Cloud Platform (GCP) project with billing enabled.
2.  `gcloud` CLI and `terraform` installed on your machine.
3.  A custom domain name (e.g., `demo.mycompany.com`) where you can modify DNS records (needed for Google-managed SSL).

### 1️⃣ Generate OAuth 2.0 Credentials (for IAP)
Identity-Aware Proxy requires OAuth credentials to authenticate users at the edge:
1.  Go to the GCP Console -> **APIs & Services** -> **Credentials**.
2.  Click **Create Credentials** -> **OAuth client ID**.
3.  Select **Application Type**: **Web application**.
4.  Name it `Antigravity Demo IAP`.
5.  Under **Authorized redirect URIs**, add:
    `https://iap.googleapis.com/v1/oauth/clientIds/YOUR_CLIENT_ID:handleRedirect`
    *(Note: You can paste a placeholder, create it, and then edit it once the Client ID is generated).*
6.  Copy the **Client ID** and **Client Secret**.

### 2️⃣ Run the Deployment Script
Execute the deployment helper in your terminal:
```bash
./deploy.sh
```
The script will automatically:
*   Prompt you for your GCP Project, Domain, and OAuth Credentials.
*   Enable all necessary GCP APIs (Cloud Build, Artifact Registry, Cloud Run, IAP, Vertex AI).
*   Create a Docker repository and submit the project to **Google Cloud Build** (compiling the C++ terminal bindings in the cloud—no local Docker required!).
*   Initialize and run **Terraform** to provision the Cloud Run service, Service Account, global static IP, HTTPS Load Balancer, SSL certificates, and IAP configurations.

### 3️⃣ Point DNS to your Load Balancer
At the end of the deployment, the script will print a static global IP address (e.g., `34.120.25.80`).
*   Go to your DNS provider (e.g., Google Domains, Route53, GoDaddy).
*   Create an **A-record** pointing your custom domain (e.g., `demo.mycompany.com`) to that IP address.
*   *Note: It takes 15 to 60 minutes for Google to provision and validate the SSL certificate after the DNS is configured.*

### 4️⃣ Authorize Users via IAP
By default, access is blocked for security. You must authorize users to access the URL:
1.  Go to GCP Console -> **Security** -> **Identity-Aware Proxy**.
2.  Under the **HTTPS Resources** tab, find `agy-demo-backend-service`.
3.  Select it, and on the right-hand panel, click **Add Principal**.
4.  Add the email addresses of the visitors (e.g., the CTO's email, or a whole corporate domain like `clientcompany.com`).
5.  Assign the Role: **Cloud IAP** -> **IAP-secured Web App User**.
6.  Save changes.

---

## 🎯 Guided Demo Walkthrough

Once the domain is active (HTTPS is green), open the link. You will see a dark terminal displaying a standard `bash` prompt, pre-cloned into `/workspace/todo-app`.

Use the buttons on the left to walk through the features:

1.  **Step 1: Understand Codebase**
    *   **Action**: Simulates typing `agy --prompt='Explain the structure of this project. What are the key files?'`
    *   **Demonstrates**: Antigravity's repository indexing and semantic code explanation. The agent will read files and print a high-level architectural overview of the Flask app.
2.  **Step 2: Diagnose Bug**
    *   **Action**: Types `agy --prompt='The delete endpoint is failing in unit tests. Find the bug in app.py.'`
    *   **Demonstrates**: Bug identification. The agent will locate the type mismatch in the `delete_task` route (comparing string `task_id` with integer IDs) and explain the issue.
3.  **Step 3: Fix & Verify Bug**
    *   **Action**: Types `agy --prompt='Fix the delete bug in app.py and run pytest to verify the fix.'`
    *   **Demonstrates**: Interactive code modification and verification. The agent will edit `app.py` directly, cast the parameter to an integer, and execute the test suite to show a green pass.
4.  **Step 4: Add Feature**
    *   **Action**: Types `agy --prompt='Add a "priority" field (low, medium, high) to tasks. Update the API and write a test for it.'`
    *   **Demonstrates**: Complex software engineering capabilities. The agent will extend the in-memory data model, update the Flask endpoints, add corresponding test assertions, and verify them.
5.  **Reset Environment** (Sidebar bottom)
    *   **Action**: Types `git reset --hard HEAD && git clean -fd`
    *   **Demonstrates**: Restores the repository back to its original buggy state, allowing you to run the demo again instantly.
