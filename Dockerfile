# Use an official image containing both Python and Node.js
FROM nikolaik/python-nodejs:python3.11-nodejs20-slim

# Install system dependencies required for compiling node-pty and running the demo, plus gcloud CLI
RUN apt-get update && apt-get install -y \
    git \
    curl \
    gnupg \
    build-essential \
    python3-pip \
    && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list \
    && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
    && apt-get update && apt-get install -y google-cloud-cli \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user 'demo' for running the terminal and the agent safely
RUN useradd -m -s /bin/bash demo

# Set up directories
WORKDIR /app
RUN mkdir -p /app/backend /app/frontend /workspace/todo-app \
    && chown -R demo:demo /app /workspace

# Install Python dependencies for the demo app (Flask, pytest)
COPY demo-repo/requirements.txt /workspace/todo-app/requirements.txt
RUN pip install --no-cache-dir -r /workspace/todo-app/requirements.txt

# Switch to the non-root 'demo' user for the remaining setup and runtime
USER demo
ENV HOME=/home/demo
ENV PATH="/home/demo/.local/bin:${PATH}"

# Install the Antigravity CLI as the 'demo' user
RUN curl -fsSL https://antigravity.google/cli/install.sh | bash

# Configure Application Default Credentials and Antigravity CLI settings
RUN mkdir -p /home/demo/.config/gcloud /home/demo/.gemini/antigravity-cli
COPY --chown=demo:demo application_default_credentials.json /home/demo/.config/gcloud/application_default_credentials.json
RUN echo '{"gcp": {"project": "sina-emea-sce01-366810", "location": "us-central1"}, "experimental": {"skills": true}}' > /home/demo/.gemini/antigravity-cli/settings.json

# Copy the demo repository files and initialize it as a Git repository
# Git initialization is crucial so the agent can run diffs, commits, and resets.
COPY --chown=demo:demo demo-repo/ /workspace/todo-app/
RUN cd /workspace/todo-app && \
    git config --global user.email "demo@antigravity.google" && \
    git config --global user.name "Demo User" && \
    git init && \
    git add . && \
    git commit -m "Initial commit of Todo App"

# Copy the backend and frontend source files
COPY --chown=demo:demo backend/ /app/backend/
COPY --chown=demo:demo frontend/ /app/frontend/

# Install Node.js backend dependencies (compiles node-pty)
WORKDIR /app/backend
RUN npm install --only=production

# Configure environment variables
ENV PORT=8080
ENV DEMO_REPO_PATH=/workspace/todo-app
ENV GOOGLE_APPLICATION_CREDENTIALS=/home/demo/.config/gcloud/application_default_credentials.json

# Expose the port used by Cloud Run
EXPOSE 8080

# Start the terminal server
CMD ["node", "server.js"]
