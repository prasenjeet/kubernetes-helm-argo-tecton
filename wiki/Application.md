# Application

The sample application is a minimal Python Flask service that demonstrates the deployment patterns in this project. Its only purpose is to provide stable, observable HTTP endpoints for health checks and deployment verification.

## Source Layout

```
app/
├── src/
│   └── app.py          Flask application
├── tests/
│   └── test_app.py     pytest test suite
├── Dockerfile          Multi-stage build (test + production targets)
├── requirements.txt    Python dependencies
└── .dockerignore
```

## Endpoints

| Method | Path | Description | Response |
|---|---|---|---|
| `GET` | `/` | Application info | `{"message": "...", "version": "...", "environment": "..."}` |
| `GET` | `/health` | Kubernetes liveness probe | `{"status": "healthy"}` — HTTP 200 |
| `GET` | `/ready` | Kubernetes readiness probe | `{"status": "ready"}` — HTTP 200 |

### Sample `/` Response

```json
{
  "message": "Hello from Sample App!",
  "version": "1.0.0",
  "environment": "staging"
}
```

Both `version` and `environment` are set via environment variables injected from the Helm `ConfigMap`.

## Environment Variables

| Variable | Default | Source |
|---|---|---|
| `APP_VERSION` | `1.0.0` | Helm `values.yaml` → ConfigMap |
| `ENVIRONMENT` | `development` | Helm `values.yaml` → ConfigMap |
| `PORT` | `8080` | Helm `values.yaml` → ConfigMap |

## Dockerfile

The image uses a two-stage build:

```
Stage: base
  python:3.12-slim
  Install dependencies from requirements.txt
  Copy src/

Stage: test   (extends base)
  Copy tests/
  RUN pytest tests/ -v
  (used by Tekton run-tests task)

Stage: production   (extends base)
  EXPOSE 8080
  CMD gunicorn --bind 0.0.0.0:8080 --workers 2 src.app:app
  (the image pushed to the registry)
```

The `test` stage runs during the Tekton `build-push-image` task to prevent broken images from being pushed. The `production` stage is what runs in Kubernetes.

## Running Locally

```bash
cd app

# Install dependencies
pip install -r requirements.txt

# Run the development server
python src/app.py
# Listening on http://0.0.0.0:8080

# Or with gunicorn (matches production)
gunicorn --bind 0.0.0.0:8080 --workers 2 src.app:app
```

## Running Tests

```bash
cd app
python -m pytest tests/ -v
```

Expected output:

```
tests/test_app.py::test_index  PASSED
tests/test_app.py::test_health PASSED
tests/test_app.py::test_ready  PASSED
3 passed in 0.12s
```

## Building the Image Locally

```bash
# Build test stage (runs pytest inside)
docker build --target test -t sample-app:test app/

# Build production image
docker build --target production -t sample-app:1.0.0 app/

# Run locally
docker run -p 8080:8080 \
  -e ENVIRONMENT=local \
  -e APP_VERSION=dev \
  sample-app:1.0.0
```

## Security

The container runs with the following hardened defaults (set in `helm/sample-app/values.yaml`):

| Setting | Value |
|---|---|
| `runAsNonRoot` | `true` |
| `runAsUser` | `1000` |
| `readOnlyRootFilesystem` | `true` |
| `allowPrivilegeEscalation` | `false` |
| `capabilities.drop` | `["ALL"]` |

A writable `/tmp` volume is mounted so Gunicorn can create its temp files.

## Extending the Application

To add a new endpoint:

1. Add the route to `app/src/app.py`.
2. Add a test to `app/tests/test_app.py`.
3. If the endpoint is environment-specific, add the config key to `helm/sample-app/values.yaml` under `env:` and read it via `os.getenv()`.
4. Push to `main` — Tekton will build, test, and deploy automatically.
