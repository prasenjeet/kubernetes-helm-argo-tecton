# Getting Started

## Prerequisites

| Tool | Minimum version | Notes |
|---|---|---|
| Kubernetes | 1.27 | Any distribution (EKS, GKE, AKS, k3s, kind) |
| kubectl | 1.27 | Configured against your target cluster |
| Helm | 3.14 | `brew install helm` / `choco install kubernetes-helm` |
| Git | 2.x | |
| Docker / Buildah | any | Only needed for local image builds |

For the full Tekton + Argo CD path you also need:

- A container registry account (GHCR, Docker Hub, ECR, etc.)
- An SSH key pair for the GitOps commit-back step

For the Harness CD path you also need:

- A [Harness account](https://app.harness.io) (free tier available)
- `HARNESS_ACCOUNT_ID` and a Delegate token from **Account Settings → Delegates**

---

## Clone the Repository

```bash
git clone https://github.com/prasenjeet/kubernetes-helm-argo-tecton.git
cd kubernetes-helm-argo-tecton
```

---

## Choose Your CD Path

| | Path A: Argo CD | Path B: Harness CD |
|---|---|---|
| Model | Pull-based GitOps | Push-based with approval gate |
| Cluster exposure | None required | None required (Delegate in cluster) |
| Best for | Pure GitOps teams | Enterprise governance + audit |
| Setup complexity | Medium | Medium–High (requires Harness account) |

You can run both paths simultaneously — they are independent and use different namespaces.

---

## Path A — Argo CD Setup

### Step 1 — Install Argo CD

```bash
bash argocd/install/install.sh
```

Wait for the server to become ready (the script waits automatically), then retrieve the initial password:

```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

Access the UI:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open https://localhost:8080  (user: admin)
```

### Step 2 — Install Tekton

```bash
bash tekton/install/install.sh
```

Access the Tekton Dashboard:

```bash
kubectl port-forward svc/tekton-dashboard -n tekton-pipelines 9097:9097
# Open http://localhost:9097
```

### Step 3 — Create Tekton Secrets

```bash
# GitHub webhook HMAC secret (choose any value, set the same in GitHub)
kubectl create secret generic github-webhook-secret \
  -n tekton-pipelines \
  --from-literal=secret=<your-webhook-hmac-secret>

# Container registry credentials
kubectl create secret docker-registry registry-credentials \
  -n tekton-pipelines \
  --docker-server=ghcr.io \
  --docker-username=<github-username> \
  --docker-password=<github-pat-token>

# SSH key for GitOps commit-back
kubectl create secret generic git-ssh-credentials \
  -n tekton-pipelines \
  --from-file=id_rsa=~/.ssh/id_rsa \
  --from-file=known_hosts=~/.ssh/known_hosts
```

### Step 4 — Apply Tekton Resources

```bash
kubectl apply -f tekton/tasks/
kubectl apply -f tekton/pipelines/
kubectl apply -f tekton/triggers/rbac.yaml
kubectl apply -f tekton/triggers/triggerbinding.yaml
kubectl apply -f tekton/triggers/triggertemplate.yaml
kubectl apply -f tekton/triggers/eventlistener.yaml
```

### Step 5 — Apply Argo CD Resources

```bash
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/application-staging.yaml
kubectl apply -f argocd/application-production.yaml
```

### Step 6 — Configure the GitHub Webhook

Get the EventListener service IP/port:

```bash
kubectl get svc -n tekton-pipelines | grep el-github
```

In GitHub → Repository → **Settings → Webhooks → Add webhook**:

| Field | Value |
|---|---|
| Payload URL | `http://<external-ip>:8080` |
| Content type | `application/json` |
| Secret | Value from step 3 |
| Events | `push` only |

---

## Path B — Harness CD Setup

### Step 1 — Install the Harness Delegate

```bash
export HARNESS_ACCOUNT_ID=<your-account-id>
export HARNESS_DELEGATE_TOKEN=<delegate-token>
bash harness/delegate/install.sh
```

Verify registration in the Harness UI under **Account Settings → Delegates**.

### Step 2 — Create Harness Secrets

In the Harness UI go to **Account Settings → Secrets → + New Secret → Text** and create:

| Identifier | Value |
|---|---|
| `github_username` | Your GitHub username |
| `github_pat_token` | GitHub PAT with `repo` + `write:packages` |
| `harness_delegate_token` | Same token used in step 1 |
| `webhook_secret` | HMAC secret for the GitHub webhook |

### Step 3 — Import Harness Resources

Use the Harness CLI or the UI **Import from Git** feature:

```bash
harness apply -f harness/connectors/
harness apply -f harness/services/
harness apply -f harness/environments/
harness apply -f harness/infrastructure/
harness apply -f harness/pipelines/
harness apply -f harness/triggers/
```

### Step 4 — Verify

Trigger a manual run in the Harness UI:  
**CD → Pipelines → Deploy Sample App → Run Pipeline**  
Set `imageTag` to any existing tag in your registry.

---

## Verify the Application

Once deployed to either environment:

```bash
# Port-forward to staging
kubectl port-forward svc/sample-app-staging -n sample-app-staging 8080:80

curl http://localhost:8080/
# {"message": "Hello from Sample App!", "version": "...", "environment": "staging"}

curl http://localhost:8080/health
# {"status": "healthy"}
```

---

## Run Tests Locally

```bash
cd app
pip install -r requirements.txt
python -m pytest tests/ -v
```

---

## Tear Down

```bash
# Remove application namespaces
kubectl delete namespace sample-app-staging sample-app-production

# Remove Argo CD
kubectl delete namespace argocd

# Remove Tekton
kubectl delete namespace tekton-pipelines

# Remove Harness Delegate
kubectl delete namespace harness-delegate-ng
```
