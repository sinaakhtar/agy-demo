#!/bin/bash
set -e

# =====================================================================
# Configuration Variables (Can be set via env vars or edited here)
# =====================================================================
PROJECT_ID="${PROJECT_ID:-"sina-emea-sce01-366810"}"
REGION="${REGION:-"us-central1"}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color
BOLD='\033[1m'

echo -e "${GREEN}${BOLD}====================================================="
echo -e "   Antigravity Direct IAP Demo Platform Deployer      "
echo -e "=====================================================${NC}"

# Ensure gcloud is in PATH (standard location on this machine)
export PATH="$HOME/google-cloud-sdk/bin:$PATH"

# Ensure local bin is in PATH
export PATH="$PWD/bin:$HOME/.local/bin:$PATH"

# 1. Check for required command-line tools (with auto-install for Terraform)
echo -e "\n${YELLOW}Checking dependencies...${NC}"

if ! command -v gcloud &> /dev/null; then
  echo -e "${RED}Error: 'gcloud' is not installed or not in PATH.${NC}"
  echo -e "Please ensure Google Cloud SDK is installed.${NC}"
  exit 1
fi
echo -e "${GREEN}gcloud CLI found.${NC}"

if ! command -v terraform &> /dev/null; then
  echo -e "${YELLOW}Terraform not found in PATH. Downloading stable binary locally...${NC}"
  mkdir -p bin
  
  TF_VERSION="1.8.5"
  TF_ZIP="terraform_${TF_VERSION}_linux_amd64.zip"
  TF_URL="https://releases.hashicorp.com/terraform/${TF_VERSION}/${TF_ZIP}"
  
  echo "Downloading Terraform v${TF_VERSION}..."
  curl -fsSL -o terraform.zip "$TF_URL"
  
  echo "Extracting Terraform using Python..."
  python3 -c "import zipfile; zipfile.ZipFile('terraform.zip').extractall('bin')"
  rm terraform.zip
  chmod +x bin/terraform
  
  echo -e "${GREEN}Terraform successfully installed locally at ./bin/terraform${NC}"
else
  echo -e "${GREEN}Terraform CLI found.${NC}"
fi

# 2. Set active gcloud project
echo -e "\n${YELLOW}Setting active GCP project to: ${BOLD}${PROJECT_ID}${NC}..."
gcloud config set project "$PROJECT_ID"

# 3. Enable required GCP services
echo -e "\n${YELLOW}Enabling required Google Cloud APIs...${NC}"
gcloud services enable \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  run.googleapis.com \
  aiplatform.googleapis.com \
  compute.googleapis.com \
  iap.googleapis.com

# 4. Set up Artifact Registry repository for the Docker image
REPO_NAME="agy-demo-repo"
echo -e "\n${YELLOW}Setting up Artifact Registry repository '${REPO_NAME}'...${NC}"
if ! gcloud artifacts repositories describe "$REPO_NAME" --location="$REGION" &>/dev/null; then
  gcloud artifacts repositories create "$REPO_NAME" \
    --repository-format=docker \
    --location="$REGION" \
    --description="Docker repository for Antigravity Demo"
else
  echo "Repository already exists."
fi

# Determine full Docker image URI
IMAGE_URI="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/antigravity-demo:latest"

# 5. Build and Push the Docker container using Google Cloud Build
echo -e "\n${YELLOW}Generating human user OAuth token for CLI authentication...${NC}"
python3 -c '
import json, subprocess

with open("/usr/local/google/home/sinanek/.config/gcloud/application_default_credentials.json") as f:
    adc = json.load(f)

res = subprocess.check_output([
    "curl", "-s", "-X", "POST", "https://oauth2.googleapis.com/token",
    "-d", f"client_id={adc[\"client_id\"]}",
    "-d", f"client_secret={adc[\"client_secret\"]}",
    "-d", f"refresh_token={adc[\"refresh_token\"]}",
    "-d", "grant_type=refresh_token"
])
data = json.loads(res)
if "access_token" not in data:
    raise Exception(f"Failed to refresh token: {data}")

token_data = {
    "token": {
        "access_token": data["access_token"],
        "token_type": "Bearer",
        "refresh_token": adc["refresh_token"],
        "expiry": "2026-06-25T12:00:00Z"
    },
    "auth_method": "browser",
    "project_id": "sina-emea-sce01-366810",
    "region": "us-central1"
}

with open("antigravity-oauth-token", "w") as f:
    json.dump(token_data, f, indent=2)
print("antigravity-oauth-token generated successfully.")
'
echo -e "\n${YELLOW}Building and pushing Docker container via Cloud Build...${NC}"
gcloud builds submit --tag "$IMAGE_URI" .

# 6. Run Terraform Deployment
echo -e "\n${YELLOW}Initializing and applying Terraform...${NC}"
cd terraform

# Create terraform.tfvars dynamically
cat > terraform.tfvars <<EOF
project_id   = "${PROJECT_ID}"
region       = "${REGION}"
image_uri    = "${IMAGE_URI}"
EOF

terraform init
terraform apply -auto-approve

# Extract outputs
DEMO_URL=$(terraform output -raw demo_url)

# 7. Print Completion Details
echo -e "\n${GREEN}${BOLD}====================================================="
echo -e "       Deployment Completed Successfully!            "
echo -e "=====================================================${NC}"
echo -e "\nTo complete your setup, follow these remaining steps:"
echo -e "\n${BOLD}Step 1: Ensure OAuth Consent Screen is Configured${NC}"
echo -e "Before IAP can authenticate users, your project must have an active OAuth Consent Screen:"
echo -e "  1. Go to GCP Console -> APIs & Services -> OAuth consent screen"
echo -e "  2. Ensure it is configured (Internal is recommended for company-only access)."

echo -e "\n${BOLD}Step 2: Grant User Access in IAP${NC}"
echo -e "By default, access is blocked. You must authorize users via IAM:"
echo -e "  1. Go to GCP Console -> Security -> Identity-Aware Proxy"
echo -e "  2. Under the 'Applications' or 'Cloud Run' section, find your service: ${BOLD}antigravity-demo${NC}"
echo -e "  3. Select it, click 'Add Principal' on the right panel"
echo -e "  4. Add the email addresses of the users (e.g., the CTO's email)"
echo -e "  5. Assign the Role: ${BOLD}Cloud IAP -> IAP-secured Web App User${NC}"

echo -e "\n${BOLD}Secure Demo URL:${NC} ${GREEN}${BOLD}${DEMO_URL}${NC}"
echo -e "====================================================="
