# Argo CD

Argo CD provides pull-based GitOps delivery. It continuously reconciles the cluster state to match the Helm chart and values files committed to this repository.

## Installation

```bash
bash argocd/install/install.sh
```

This installs Argo CD `v2.11.0` into the `argocd` namespace and waits for the server to be ready.

After installation:

```bash
# Retrieve the initial admin password
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d && echo

# Access the UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Visit https://localhost:8080  (username: admin)

# Or install the CLI
brew install argocd
argocd login localhost:8080 --username admin --insecure
```

## AppProject

`argocd/project.yaml` defines an `AppProject` named `sample-app` that scopes what the Applications in this project are allowed to do.

### Source Repositories

Only this repository may be used as a source:

```yaml
sourceRepos:
  - https://github.com/example/kubernetes-helm-argo-tecton.git
```

### Allowed Destinations

```yaml
destinations:
  - namespace: sample-app-staging
    server: https://kubernetes.default.svc
  - namespace: sample-app-production
    server: https://kubernetes.default.svc
```

Applications in this project cannot deploy to any other namespace or cluster.

### RBAC Roles

| Role | Permissions | Group |
|---|---|---|
| `developer` | get, sync | `developers` |
| `admin` | all actions | `platform-team` |

Apply the project before the Applications:

```bash
kubectl apply -f argocd/project.yaml
```

## Staging Application

`argocd/application-staging.yaml` — deploys to `sample-app-staging` with **automated sync**.

```yaml
syncPolicy:
  automated:
    prune: true       # Remove resources no longer in Git
    selfHeal: true    # Revert manual kubectl changes
    allowEmpty: false # Never sync an empty state
  retry:
    limit: 5
    backoff: { duration: 5s, factor: 2, maxDuration: 3m }
```

The image tag is updated by the Tekton `update-image-tag` task. Argo CD detects the diff in `values-staging.yaml` and syncs within the default polling interval (3 minutes) or immediately if a webhook is configured.

```bash
kubectl apply -f argocd/application-staging.yaml
```

## Production Application

`argocd/application-production.yaml` — deploys to `sample-app-production` with **manual sync only** (no `automated` block).

```bash
kubectl apply -f argocd/application-production.yaml
```

To promote to production:

```bash
# Via CLI
argocd app sync sample-app-production

# Via UI
# CD → Applications → sample-app-production → Sync
```

## Sync Options

Both applications use:

| Option | Effect |
|---|---|
| `CreateNamespace=true` | Creates the target namespace if it does not exist |
| `PrunePropagationPolicy=foreground` | Waits for deleted resources to be fully removed |
| `PruneLast=true` | Prunes resources after new resources are healthy |

## Webhook (Optional — reduces sync latency)

To trigger an immediate sync on push instead of waiting for the polling interval:

1. Go to `https://localhost:8080/settings/repos` and find the repository.
2. Copy the **webhook URL** (format: `https://<argocd-server>/api/webhook`).
3. Add it as a GitHub webhook with content type `application/json`.
4. Argo CD will sync within seconds of a push.

## Rollback

```bash
# List sync history
argocd app history sample-app-staging

# Roll back to revision N
argocd app rollback sample-app-staging <revision-id>
```

Alternatively, revert the commit in Git and let Argo CD auto-sync (staging) or manually sync (production).

## Monitoring Application Health

```bash
# Watch sync and health status
argocd app get sample-app-staging
argocd app get sample-app-production

# Wait for healthy/synced
argocd app wait sample-app-staging --health --sync

# Live resource diff (Git vs cluster)
argocd app diff sample-app-staging
```

## Notifications (Optional)

Argo CD Notifications can send Slack/email/Teams messages on sync events. To enable:

```bash
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj-labs/argocd-notifications/stable/manifests/install.yaml
```

Configure triggers and templates in `argocd-notifications-cm` ConfigMap.

## Common Issues

| Problem | Cause | Fix |
|---|---|---|
| App stuck in `OutOfSync` | `selfHeal: true` but cluster has drift it can't fix | Check `argocd app get` for resource errors |
| `ComparisonError` | Helm template render failure | Run `helm template` locally to find the error |
| Sync loop | `update-image-tag` task pushes without `[skip ci]` | Ensure the git commit message contains `[skip ci]` |
| Image pull error | Registry credentials missing | Create `imagePullSecrets` and add to `values.yaml` |
