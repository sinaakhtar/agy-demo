# Antigravity CLI Cloud Run Demo Handoff & Debugging Summary

## 📌 Project Overview
* **Objective:** Deploy an interactive browser-based terminal demo of the Antigravity CLI (`agy`) to Cloud Run with pre-programmed feature prompts, protected by Identity-Aware Proxy (IAP).
* **Local Project Path:** `~/code/agy-demo`
* **GitHub Repository:** [https://github.com/sinaakhtar/agy-demo](https://github.com/sinaakhtar/agy-demo)
* **GCP Project:** `sina-emea-sce01-366810` (Project Number: `821194225645`)
* **Cloud Run Service:** `https://antigravity-demo-gj7q7gb3jq-uc.a.run.app`

---

## 🔍 Current Status & Symptoms
When running `agy` inside the container's web terminal:
1. **When `USE_ADC=true` (Service Account Auth):**
   Fails with `Failed to poll ListExperiments: error getting token source: You are not logged into Antigravity` followed by `403 PERMISSION_DENIED: Cloud Code Private API has not been used in project 821194225645 before or it is disabled.`
2. **When `USE_ADC=false` (Human OAuth):**
   Bypasses the OOM/ADC failure screen, but drops the user onto the interactive `Select login method: 1. Google OAuth, 2. Use a Google Cloud project` menu instead of automatically logging in.

---

## 🧠 Codebase Insights (`third_party/jetski`)
* **Backend Auth Routing (`third_party/jetski/cli/backend/server.go` & `server_oauth.go`):**
  * When `USE_ADC=true`, `ServerBackend` initializes `cfg.adcAuth` (Service Account). `CodeAssistClient` startup unconditionally fires `fetchUserInfo` and `fetchAvailableModels` RPCs to `https://cloudcode-pa.googleapis.com`. GCP API Gateway charges quota to project `821194225645`, which returns 403 because `cloudcode-pa` is a restricted internal Google API.
  * Note: `SetQuotaProjectFetcher` in `server.go` checks `active.Name() == "gcp"`, skipping `readGCPSettings` when `active.Name()` is `"adc"`.
* **Keyring vs File Storage Fallback (`third_party/jetski/cli/backend/auth/token_storage.go` & `keyring.go`):**
  * When `USE_ADC=false`, `ServerBackend` uses `NewDefaultChain` (`keyringAuth` + `browserOAuth`).
  * On headless Linux / Docker, `shouldBypassKeyring()` returns `true` and falls back to file token storage.
  * Expected token file path: `/home/demo/.gemini/antigravity-cli/antigravity-oauth-token` (or `~/.gemini/antigravity-oauth-token`).
  * Expected JSON structure:
    ```json
    {
      "token": {
        "access_token": "ya29...",
        "token_type": "Bearer",
        "refresh_token": "1//0...",
        "expiry": "2026-06-25T12:00:00Z"
      },
      "auth_method": "consumer",
      "project_id": "sina-emea-sce01-366810",
      "region": "us-central1"
    }
    ```
  * *Critical Key:* `getOauthParams(authMethod)` in `browser.go` expects `"consumer"` (not `"browser"`).
* **CLI AppData Directory (`agy 1.0.10+`):**
  * Config paths moved from `~/.agy` to `~/.gemini`.
  * Settings file: `/home/demo/.gemini/antigravity-cli/settings.json`

---

## 🛠️ Actions Taken So Far
1. **Platform Architecture:** Built frontend (`xterm.js`) + backend (`express` + `ws` + `node-pty`).
2. **Infrastructure (Terraform):** Configured Cloud Run service with Direct IAP (`iap_enabled = true`).
3. **Container Environment (`Dockerfile`):** Installed `google-cloud-cli`, `python3-pip`, Node.js runtime.
4. **Secret Handling:** Created `.gitignore` and `.gcloudignore` to keep secrets local while ensuring Cloud Build uploads `antigravity-oauth-token`.
5. **Token Generator (`deploy.sh`):** Added Python routine to parse workstation ADC (`~/.config/gcloud/application_default_credentials.json`), call `https://oauth2.googleapis.com/token`, and pre-seed `./antigravity-oauth-token`.
6. **Git Sync:** Pushed clean code (excluding state & secrets) to GitHub.

---

## 🚀 Recommended Next Steps for Receiving Agent
1. **Debug Silent Token Loading:**
   Launch `agy` inside the container terminal with verbose logging:
   ```bash
   agy --cli_log_file=/tmp/agy_debug.log
   cat /tmp/agy_debug.log
   ```
   Inspect why `keyringAuth.TryAuth` returns `nil` when reading `/home/demo/.gemini/antigravity-cli/antigravity-oauth-token`.
2. **Verify AppDataDir / Path Resolution:**
   Check log line from earlier runs: `Failed to resolve GeminiDir ".gemini": .gemini must be an absolute path: path is not absolute, falling back to default`. Test copying `antigravity-oauth-token` to `/home/demo/.gemini/antigravity-oauth-token` (parent dir) in addition to `/home/demo/.gemini/antigravity-cli/antigravity-oauth-token`.
3. **Check `installation_id` file:**
   YAQS thread `go/yeng/2970923299204235264` notes headless CI runs require both `antigravity-oauth-token` and an `installation_id` file (UUID string) in the config directory.
