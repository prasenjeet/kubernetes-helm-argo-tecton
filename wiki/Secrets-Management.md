# Secrets Management

This page documents every secret required by the project, where it is stored, and how to create it. No secret values are ever committed to Git.

## Principle

| Rule | Rationale |
|---|---|
| Secrets live outside Git | Git history is permanent and shared |
| Reference secrets by name | YAML files contain identifiers, never values |
| Rotate on compromise | Each secret is scoped to a single purpose |
| Least privilege | Credentials are scoped to minimum required access |

---

## Tekton Secrets

Tekton reads secrets from Kubernetes `Secret` objects in the `tekton-pipelines` namespace.

### `github-webhook-secret`

Used by the GitHub interceptor in the EventListener to validate that incoming webhooks originate from GitHub.

```bash
kubectl create secret generic github-webhook-secret \
  -n tekton-pipelines \
  --from-literal=secret=<choose-any-strong-random-string>
```

Set the same value in **GitHub → Repository → Settings → Webhooks → Secret**.

### `registry-credentials`

Docker config credentials for pushing built images to the container registry.

```bash
# GHCR (GitHub Container Registry)
kubectl create secret docker-registry registry-credentials \
  -n tekton-pipelines \
  --docker-server=ghcr.io \
  --docker-username=<github-username> \
  --docker-password=<github-pat-with-write:packages>

# Docker Hub
kubectl create secret docker-registry registry-credentials \
  -n tekton-pipelines \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=<dockerhub-username> \
  --docker-password=<dockerhub-access-token>
```

The PAT needs the `write:packages` scope for GHCR.

### `git-ssh-credentials`

SSH key used by the `update-image-tag` task to push the GitOps commit back to the repository.

```bash
# Generate a dedicated deploy key (do not reuse your personal key)
ssh-keygen -t ed25519 -C "tekton-gitops-bot" -f /tmp/tekton-gitops-key -N ""

# Add the PUBLIC key as a GitHub Deploy Key with write access:
# Repository → Settings → Deploy Keys → Add deploy key
# Paste contents of /tmp/tekton-gitops-key.pub

# Create the Kubernetes Secret from the PRIVATE key
ssh-keyscan github.com > /tmp/known_hosts
kubectl create secret generic git-ssh-credentials \
  -n tekton-pipelines \
  --from-file=id_rsa=/tmp/tekton-gitops-key \
  --from-file=known_hosts=/tmp/known_hosts

# Clean up temp files
rm /tmp/tekton-gitops-key /tmp/tekton-gitops-key.pub /tmp/known_hosts
```

---

## Argo CD Secrets

Argo CD manages its own secrets in the `argocd` namespace.

### Initial Admin Password

Set automatically on install. Retrieve with:

```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

Change the password after first login:

```bash
argocd account update-password
```

### Repository Credentials

If the repository is private, add credentials in the Argo CD UI under **Settings → Repositories**, or via the CLI:

```bash
# HTTPS with PAT
argocd repo add https://github.com/example/kubernetes-helm-argo-tecton.git \
  --username <github-username> \
  --password <github-pat>

# SSH
argocd repo add git@github.com:example/kubernetes-helm-argo-tecton.git \
  --ssh-private-key-path ~/.ssh/id_ed25519
```

### Image Pull Secrets (Optional)

If the container registry is private, add the pull secret to the target namespaces and reference it in Helm values:

```bash
kubectl create secret docker-registry ghcr-pull-secret \
  -n sample-app-staging \
  --docker-server=ghcr.io \
  --docker-username=<username> \
  --docker-password=<pat>

kubectl create secret docker-registry ghcr-pull-secret \
  -n sample-app-production \
  --docker-server=ghcr.io \
  --docker-username=<username> \
  --docker-password=<pat>
```

Then in `values.yaml`:

```yaml
imagePullSecrets:
  - name: ghcr-pull-secret
```

---

## Harness CD Secrets

Harness secrets are stored in the **Harness Secret Manager** (cloud-hosted, encrypted at rest). They are never stored in Git.

Create secrets at: **Harness UI → Account Settings → Secrets → + New Secret → Text**

| Identifier | Type | Scope | Description |
|---|---|---|---|
| `github_username` | Text | Account | GitHub username |
| `github_pat_token` | Text | Account | GitHub PAT (`repo` + `write:packages`) |
| `harness_delegate_token` | Text | Account | Token for delegate authentication |
| `webhook_secret` | Text | Account | HMAC secret for GitHub webhook |

Reference secrets in YAML using the expression `<+secrets.getValue("identifier")>`.

### GitHub PAT Required Scopes

| Scope | Required For |
|---|---|
| `repo` | Read private repository |
| `read:packages` | Pull images from GHCR |
| `write:packages` | Push images to GHCR (Tekton step) |

---

## Secret Rotation

### Rotating the Webhook HMAC Secret

1. Generate a new random string: `openssl rand -hex 32`
2. Update the Kubernetes Secret in `tekton-pipelines`:
   ```bash
   kubectl create secret generic github-webhook-secret \
     -n tekton-pipelines \
     --from-literal=secret=<new-value> \
     --dry-run=client -o yaml | kubectl apply -f -
   ```
3. Update the secret in GitHub → Repository → Settings → Webhooks.
4. Update `webhook_secret` in the Harness Secret Manager if using the Harness webhook trigger.

### Rotating Registry Credentials

```bash
kubectl create secret docker-registry registry-credentials \
  -n tekton-pipelines \
  --docker-server=ghcr.io \
  --docker-username=<username> \
  --docker-password=<new-pat> \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Rotating the Git SSH Deploy Key

1. Generate a new key pair.
2. Replace the Deploy Key in GitHub Repository → Settings → Deploy Keys.
3. Update the Kubernetes Secret:
   ```bash
   kubectl create secret generic git-ssh-credentials \
     -n tekton-pipelines \
     --from-file=id_rsa=<new-private-key-path> \
     --from-file=known_hosts=<known_hosts-path> \
     --dry-run=client -o yaml | kubectl apply -f -
   ```

---

## Auditing

- **Kubernetes Secrets**: `kubectl get events -n tekton-pipelines` shows Secret access events if audit logging is enabled.
- **Argo CD**: Sync history records which Git revision was deployed and by whom.
- **Harness CD**: Execution history records approver name, change ticket, and image tag for every deployment.
