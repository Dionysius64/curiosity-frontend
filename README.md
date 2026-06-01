# Curiosity Frontend

Flutter client for Curiosity targeting Windows, Android, and Web.

The current UI uses a mock lesson `CuriosityApi` implementation in `lib/main.dart`, so lesson flows are usable before the full REST client is wired to the FastAPI backend. The Logs page already calls the backend `GET /api/logs` endpoint when opened. The backend API contract is documented in `../docs/architecture_plan.md`.

## Development Testing

### Prerequisites

- Flutter SDK installed and on `PATH`.
- For Windows desktop: Visual Studio with the Desktop development with C++ workload.
- For Android: Android Studio, Android SDK, and an emulator or physical device.
- For browser: Chrome or Edge.
- No backend credentials are required while the mock lesson API is active.
- To view backend logs in the frontend Logs page, run the backend locally and pass `API_BASE_URL`.

### Test account

There is no password-based auth yet. On first launch the app asks for a name.

Use:

```text
Ada
```

Any alphabetic-only name works. Names with spaces, numbers, or punctuation are rejected to match the backend rule.

### Install dependencies

From the repository root:

```powershell
cd frontend
flutter pub get
```

### Run on Windows

```powershell
cd frontend
flutter run -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000/api
```

### Run in a browser

```powershell
cd frontend
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000/api
```

If you prefer a web-server target:

```powershell
cd frontend
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 5173 --dart-define=API_BASE_URL=http://127.0.0.1:8000/api
```

Open:

```text
http://127.0.0.1:5173
```

### Run on Android

1. Start an Android emulator from Android Studio, or connect a physical device with USB debugging enabled.
2. Confirm Flutter can see it:

```powershell
flutter devices
```

3. Run:

```powershell
cd frontend
flutter run -d android --dart-define=API_BASE_URL=http://10.0.2.2:8000/api
```

If multiple Android devices are listed, copy the device ID from `flutter devices` and run:

```powershell
flutter run -d YOUR_DEVICE_ID --dart-define=API_BASE_URL=http://10.0.2.2:8000/api
```

### Run automated checks

```powershell
cd frontend
flutter analyze
flutter test
flutter build web
```

### Local backend and logs integration

The visible lesson flow currently uses `MockCuriosityApi`, but Logs pulls backend logs from `API_BASE_URL`.

1. Run the backend:

```powershell
cd backend
$env:LLM_PROVIDER = "mock"
python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

2. Use this base URL from Windows or browser:

```text
http://127.0.0.1:8000/api
```

3. For Android emulator, use:

```text
http://10.0.2.2:8000/api
```

4. Keep backend `CORS_ORIGINS` open for local browser testing before starting the backend:

```powershell
$env:CORS_ORIGINS = "http://localhost:5173,http://127.0.0.1:5173"
```

5. Open `Settings` -> `Logs` in the frontend. Frontend logs have a yellow outline. Backend logs have a blue outline. The list is sorted newest first and capped at 200 entries.

## Deployment: Railway

References:

- Railway static hosting guide: https://docs.railway.com/guides/static-hosting
- Railway SPA routing guide: https://docs.railway.com/guides/spa-routing-configuration
- Railway public networking guide: https://docs.railway.com/networking/public-networking

This repository includes:

- `frontend/Dockerfile`
- `frontend/Caddyfile`

Railway will build Flutter web in Docker and serve `build/web` with Caddy.

### 1. Prepare the repository

1. Commit the repository to GitHub.
2. Confirm the frontend builds locally:

```powershell
cd frontend
flutter pub get
flutter analyze
flutter test
flutter build web
```

3. Confirm `frontend/Caddyfile` contains:

```text
:{$PORT} {
	root * /srv
	encode gzip
	try_files {path} /index.html
	file_server
}
```

The `try_files` rule is important for single-page app routing.

### 2. Create the Railway service

1. Sign in at https://railway.com.
2. Click `New Project`.
3. Choose `Deploy from GitHub repo`.
4. Select this repository.
5. Open the new service settings.
6. Set the service root directory to:

```text
frontend
```

7. Confirm Railway detects the `Dockerfile`. If Railway asks for a builder, choose Dockerfile.

### 3. Configure variables

The Dockerfile accepts the backend API URL as a build argument:

```text
API_BASE_URL=https://YOUR-BACKEND-DOMAIN/api
```

In Railway:

1. Open the frontend service.
2. Go to `Variables`.
3. Add:

```text
API_BASE_URL=https://YOUR-BACKEND-DOMAIN/api
```

4. Confirm the backend service has `CORS_ORIGINS` set to the Railway frontend domain after you generate it.

The Docker build passes this value into Flutter as:

```powershell
flutter build web --dart-define=API_BASE_URL=https://YOUR-BACKEND-DOMAIN/api
```

### 4. Deploy and expose the site

1. Trigger a Railway deployment.
2. Wait for a successful build and deploy.
3. Open `Settings`.
4. Find `Networking` -> `Public Networking`.
5. Click `Generate Domain`.
6. Open the generated Railway domain.
7. Enter the test name:

```text
Ada
```

8. Create a mock lesson from the Start page.
9. Open `Settings` -> `Logs` and confirm backend entries appear if the backend API URL is configured and reachable.

### 5. Connect it to the backend later

After the frontend uses the real lesson API:

1. Deploy the backend first.
2. Copy the backend public URL, ending in `/api`.
3. Configure `API_BASE_URL` with that URL.
4. Configure backend `CORS_ORIGINS` to include the frontend Railway domain.
5. Redeploy both services.

## Deployment: Azure Static Web Apps

References:

- Azure Static Web Apps overview: https://learn.microsoft.com/en-us/azure/static-web-apps/overview
- Azure Static Web Apps CLI reference: https://learn.microsoft.com/en-us/azure/static-web-apps/static-web-apps-cli

These steps deploy the Flutter web build as a static site. The backend should be deployed separately to Azure App Service or Railway.

### 1. Install tools

Install Azure CLI:

```powershell
az --version
```

If it is missing, install it from:

```text
https://learn.microsoft.com/en-us/cli/azure/install-azure-cli
```

Install Node.js LTS, then install the Static Web Apps CLI:

```powershell
npm install -g @azure/static-web-apps-cli
```

Sign in to Azure:

```powershell
az login
```

Select a subscription if needed:

```powershell
az account list --output table
az account set --subscription "YOUR_SUBSCRIPTION_ID_OR_NAME"
```

### 2. Build Flutter web

```powershell
cd frontend
flutter pub get
flutter analyze
flutter test
flutter build web --release --dart-define=API_BASE_URL=https://YOUR-BACKEND-DOMAIN/api
```

The deployable folder is:

```text
frontend/build/web
```

### 3. Create the Static Web App resource

Choose names:

```powershell
$env:AZURE_LOCATION = "westeurope"
$env:RESOURCE_GROUP = "curiosity-rg"
$env:STATIC_APP_NAME = "curiosity-web-REPLACE-WITH-UNIQUE-SUFFIX"
```

Create or reuse a resource group:

```powershell
az group create `
  --name $env:RESOURCE_GROUP `
  --location $env:AZURE_LOCATION
```

Create the Static Web App in the Azure portal:

1. Search for `Static Web Apps`.
2. Click `Create`.
3. Select the subscription.
4. Select or create `curiosity-rg`.
5. Enter a globally unique app name.
6. Select a region near your users.
7. For plan type, choose the plan you want to pay for. `Free` is enough for early testing if available.
8. For deployment source, choose `Other` if available. This enables token-based deployment from the SWA CLI.
9. If the portal requires GitHub or Azure DevOps instead, connect the repository and let Azure create the resource, then still use the deployment token flow below for manual deployments.
10. Click `Review + create`.
11. Click `Create`.
12. Wait until deployment completes.

### 4. Get the deployment token

```powershell
$env:SWA_TOKEN = az staticwebapp secrets list `
  --name $env:STATIC_APP_NAME `
  --resource-group $env:RESOURCE_GROUP `
  --query "properties.apiKey" `
  --output tsv
```

If using the Azure portal:

1. Open the Static Web App resource.
2. Go to `Overview`.
3. Click `Manage deployment token`.
4. Copy the token.
5. Set it in PowerShell:

```powershell
$env:SWA_TOKEN = "PASTE_TOKEN_HERE"
```

### 5. Deploy the built site

From `frontend`:

```powershell
swa deploy .\build\web `
  --deployment-token $env:SWA_TOKEN `
  --env production
```

### 6. Verify the site

Get the default hostname:

```powershell
az staticwebapp show `
  --name $env:STATIC_APP_NAME `
  --resource-group $env:RESOURCE_GROUP `
  --query "defaultHostname" `
  --output tsv
```

Open:

```text
https://YOUR_DEFAULT_HOSTNAME
```

Then:

1. Enter `Ada` when prompted for a name.
2. Click `Start`.
3. Create a mock lesson.
4. Open `Diary` and `Settings` from the top bar.
5. Open `Settings` -> `Logs` and confirm frontend entries are visible. Backend entries require the backend URL used at build time to be reachable and allowed by CORS.

### 7. Connect it to the backend later

After a real lesson REST client is implemented:

1. Deploy the backend and copy its public `/api` URL.
2. Use the Flutter compile-time API base URL already supported by the app.
3. Rebuild:

```powershell
flutter build web --release --dart-define=API_BASE_URL=https://YOUR-BACKEND-DOMAIN/api
```

4. Redeploy with `swa deploy`.
5. Set backend `CORS_ORIGINS` to the Azure Static Web Apps hostname.
