# Kubernetes · Helm · Argo CD · Tekton · Harness CD — Sample Project

A production-ready reference project demonstrating GitOps CI/CD on Kubernetes using:

| Tool | Role |
|---|---|
| **Flask** | Sample application |
| **Helm** | Kubernetes packaging |
| **Argo CD** | GitOps continuous delivery (pull-based) |
| **Tekton** | Cloud-native CI/CD pipelines (in-cluster) |
| **Harness CD** | Enterprise CD platform with approval gates and rollback |

## Architecture

### Path A — Tekton CI + Argo CD CD (GitOps pull model)

```
GitHub push
    │
    ▼
Tekton EventListener (webhook)
    │
    ├─ 1. git-clone        clone source repo
    ├─ 2. run-tests        pytest
    ├─ 3. build-push-image buildah → ghcr.io
    └─ 4. update-image-tag commit new tag to GitOps repo
                                │
                                ▼
                          Argo CD detects drift
                                │
                                ▼
                       helm upgrade → Kubernetes
```

### Path B — Tekton CI + Harness CD (push model with approval gates)

```
GitHub push
    │
    ▼
Tekton CI  (build + test + push image)
    │
    ├── artifact trigger ──▶ Harness CD pipeline
    │                              │
    │                    ┌─────────┴──────────┐
    │                    │                    │
    │              Deploy Staging        Approval Gate
    │              (auto)                (platform-team)
    │                    │                    │
    │                    └─────────┬──────────┘
    │                              │
    │                       Deploy Production
    │                       (Helm + health check)
    │
    └── webhook trigger ──▶ Harness CD pipeline (alternative entry)
```

## Repository Layout

```
.
├── app/                          # Sample Flask application
│   ├── src/app.py
│   ├── tests/test_app.py
│   ├── Dockerfile
│   └── requirements.txt
├── helm/
│   └── sample-app/               # Helm chart
│       ├── Chart.yaml
│       ├── values.yaml            # Base values
│       ├── values-staging.yaml
│       ├── values-production.yaml
│       └── templates/
├── argocd/
│   ├── install/install.sh        # Argo CD installation script
│   ├── project.yaml              # AppProject (RBAC)
│   ├── application-staging.yaml
│   └── application-production.yaml
├── tekton/
│   ├── install/install.sh        # Tekton installation script
│   ├── tasks/                    # Reusable Tasks
│   │   ├── git-clone.yaml
│   │   ├── run-tests.yaml
│   │   ├── build-push-image.yaml
│   │   └── update-image-tag.yaml
│   ├── pipelines/
│   │   └── ci-cd-pipeline.yaml   # Full CI/CD Pipeline
│   ├── triggers/                 # Webhook → PipelineRun
│   │   ├── rbac.yaml
│   │   ├── triggerbinding.yaml
│   │   ├── triggertemplate.yaml
│   │   └── eventlistener.yaml
│   ├── pipelineruns/
│   │   └── manual-run.yaml       # Trigger a run manually
│   └── secrets-template.yaml     # Required secrets reference
└── harness/
    ├── delegate/
    │   └── install.sh            # Install Harness K8s Delegate
    ├── connectors/               # GitHub, K8s cluster, GHCR connectors
    ├── services/
    │   └── sample-app.yaml       # Service definition (Helm source + image)
    ├── environments/             # staging.yaml, production.yaml
    ├── infrastructure/           # K8s infra definitions per environment
    ├── pipelines/
    │   ├── cd-deploy-pipeline.yaml   # Stage → Approval → Production pipeline
    │   └── rollback-pipeline.yaml    # Emergency Helm rollback
    ├── input-sets/               # Parameterized inputs for each environment
    ├── triggers/
    │   ├── artifact-trigger.yaml # Fires on new image tag in GHCR
    │   └── webhook-trigger.yaml  # Fires on GitHub push to main
    └── secrets-reference.yaml    # Required Harness secrets reference
```

## Prerequisites

- Kubernetes cluster (1.27+)
- `kubectl` configured
- `helm` 3.x
- Container registry (GHCR, Docker Hub, ECR, etc.)

## Quick Start

### 1. Install Argo CD

```bash
bash argocd/install/install.sh

# Get the initial admin password
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d

# Open the UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Visit https://localhost:8080
```

### 2. Install Tekton

```bash
bash tekton/install/install.sh

# Open the Tekton Dashboard
kubectl port-forward svc/tekton-dashboard -n tekton-pipelines 9097:9097
# Visit http://localhost:9097
```

### 3. Create Required Secrets

```bash
# GitHub webhook HMAC secret
kubectl create secret generic github-webhook-secret \
  -n tekton-pipelines \
  --from-literal=secret=<your-webhook-secret>

# Container registry credentials
kubectl create secret docker-registry registry-credentials \
  -n tekton-pipelines \
  --docker-server=ghcr.io \
  --docker-username=<github-user> \
  --docker-password=<github-token>

# SSH key for GitOps commits
kubectl create secret generic git-ssh-credentials \
  -n tekton-pipelines \
  --from-file=id_rsa=~/.ssh/id_rsa \
  --from-file=known_hosts=~/.ssh/known_hosts
```

### 4. Apply Tekton Resources

```bash
kubectl apply -f tekton/tasks/
kubectl apply -f tekton/pipelines/
kubectl apply -f tekton/triggers/rbac.yaml
kubectl apply -f tekton/triggers/triggerbinding.yaml
kubectl apply -f tekton/triggers/triggertemplate.yaml
kubectl apply -f tekton/triggers/eventlistener.yaml
```

### 5. Apply Argo CD Resources

```bash
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/application-staging.yaml
# Production is synced manually:
kubectl apply -f argocd/application-production.yaml
```

### 6. Configure the GitHub Webhook

```bash
# Get the EventListener external URL
kubectl get svc -n tekton-pipelines | grep el-github-webhook-listener
```

In your GitHub repository → Settings → Webhooks:
- **Payload URL**: `http://<external-ip>:8080`
- **Content type**: `application/json`
- **Secret**: value used in step 3
- **Events**: Just the `push` event

## Manual Pipeline Run

Trigger a pipeline without a webhook:

```bash
# Edit repo-url and image-tag first if needed
kubectl create -f tekton/pipelineruns/manual-run.yaml

# Follow the logs
kubectl get pipelineruns -n tekton-pipelines -w
```

## Deploy with Helm Directly

```bash
# Staging
helm upgrade --install sample-app-staging helm/sample-app \
  -f helm/sample-app/values.yaml \
  -f helm/sample-app/values-staging.yaml \
  --namespace sample-app-staging \
  --create-namespace

# Production
helm upgrade --install sample-app-production helm/sample-app \
  -f helm/sample-app/values.yaml \
  -f helm/sample-app/values-production.yaml \
  --namespace sample-app-production \
  --create-namespace
```

## GitOps Flow

1. Developer pushes to `main`.
2. GitHub sends a push webhook to the Tekton `EventListener`.
3. The CEL interceptor filters out `[skip ci]` commits.
4. Tekton clones the repo, runs tests, builds and pushes the image.
5. The `update-image-tag` task commits the new tag back to the repo.
6. Argo CD detects the diff in `values-staging.yaml` and auto-syncs.
7. Production requires a manual sync approval in the Argo CD UI.

## Harness CD Setup

### 1. Install the Harness Delegate

The Delegate is a lightweight agent that runs in your cluster and executes pipeline steps on behalf of Harness.

```bash
export HARNESS_ACCOUNT_ID=<your-account-id>
export HARNESS_DELEGATE_TOKEN=<token-from-harness-ui>
bash harness/delegate/install.sh
```

Verify registration at `app.harness.io → Account Settings → Delegates`.

### 2. Create Harness Secrets

Before applying connectors, create these secrets in **Harness Secret Manager** (UI or API):

| Identifier | Description |
|---|---|
| `github_username` | GitHub account username |
| `github_pat_token` | GitHub PAT (scopes: `repo`, `write:packages`) |
| `harness_delegate_token` | Delegate authentication token |
| `webhook_secret` | HMAC secret matching the GitHub webhook |

See `harness/secrets-reference.yaml` for the full list.

### 3. Apply Connectors, Service, Environments, and Infrastructure

Import each file through the Harness UI (**Resources → Import from Git**) or with the Harness CLI:

```bash
# Using the Harness CLI (harness-cli)
harness apply -f harness/connectors/
harness apply -f harness/services/
harness apply -f harness/environments/
harness apply -f harness/infrastructure/
```

### 4. Apply Pipelines and Triggers

```bash
harness apply -f harness/pipelines/cd-deploy-pipeline.yaml
harness apply -f harness/pipelines/rollback-pipeline.yaml
harness apply -f harness/triggers/artifact-trigger.yaml
harness apply -f harness/triggers/webhook-trigger.yaml
```

### 5. Run the CD Pipeline Manually

```bash
# Trigger a specific image tag through the Harness UI, or via API:
curl -X POST "https://app.harness.io/pipeline/api/pipeline/execute/Deploy_Sample_App" \
  -H "x-api-key: $HARNESS_API_KEY" \
  -H "Content-Type: application/yaml" \
  --data-binary @harness/input-sets/staging-input-set.yaml
```

### Emergency Rollback

```bash
# Via Harness UI: CD → Pipelines → Rollback Sample App → Run
# Or via API:
curl -X POST "https://app.harness.io/pipeline/api/pipeline/execute/Rollback_Sample_App" \
  -H "x-api-key: $HARNESS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"variables": [{"name": "targetEnvironment", "value": "production"}]}'
```

## Harness CD Pipeline Flow

1. Tekton builds and pushes `ghcr.io/example/sample-app:<sha>`.
2. The **artifact trigger** fires `Deploy_Sample_App` with `imageTag=<sha>`.
3. **Stage 1** — Helm deploys to `sample-app-staging`, runs an HTTP health check.
4. **Stage 2** — `HarnessApproval` step gates promotion; platform-team reviews staging.
5. **Stage 3** — Helm deploys to `sample-app-production` with production values; HTTP health check confirms live traffic.
6. On any failure, Helm rollback steps revert to the previous release automatically.

## Application Endpoints

| Path | Description |
|---|---|
| `GET /` | App info (version, environment) |
| `GET /health` | Liveness check |
| `GET /ready` | Readiness check |
