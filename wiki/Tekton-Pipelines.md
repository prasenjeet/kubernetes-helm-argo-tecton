# Tekton Pipelines

Tekton runs the CI pipeline (build, test, push) inside the cluster. Triggers respond to GitHub webhooks and create PipelineRuns automatically.

## Installation

```bash
bash tekton/install/install.sh
```

Installs:
- Tekton Pipelines `v0.59.0`
- Tekton Triggers `v0.26.2`
- Tekton Dashboard `v0.44.0`

Access the dashboard:

```bash
kubectl port-forward svc/tekton-dashboard -n tekton-pipelines 9097:9097
# Open http://localhost:9097
```

## Resource Layout

```
tekton/
├── tasks/
│   ├── git-clone.yaml          Clone a git repo into a workspace
│   ├── run-tests.yaml          Run pytest
│   ├── build-push-image.yaml   Build with Buildah and push to registry
│   └── update-image-tag.yaml   Commit new image tag to GitOps repo
├── pipelines/
│   └── ci-cd-pipeline.yaml     Chains the four tasks
├── triggers/
│   ├── rbac.yaml               ServiceAccount + RBAC for EventListener
│   ├── triggerbinding.yaml     Extract fields from GitHub push payload
│   ├── triggertemplate.yaml    Template for PipelineRun creation
│   └── eventlistener.yaml      HTTP server receiving GitHub webhooks
└── pipelineruns/
    └── manual-run.yaml         Ad-hoc PipelineRun for testing
```

## Tasks

### `git-clone`

Clones a git repository at a specified branch or commit SHA into a shared workspace.

**Params**

| Name | Default | Description |
|---|---|---|
| `url` | — | Repository URL |
| `revision` | `main` | Branch, tag, or SHA |
| `depth` | `1` | Shallow clone depth |

**Results**

| Name | Description |
|---|---|
| `commit` | Full commit SHA that was fetched |
| `url` | URL that was cloned |

**Workspaces**

| Name | Required | Description |
|---|---|---|
| `output` | Yes | Destination for cloned files |
| `ssh-directory` | No | SSH credentials for private repos |

---

### `run-tests`

Installs Python dependencies and runs `pytest` inside the container.

**Params**

| Name | Default | Description |
|---|---|---|
| `test-dir` | `app` | Path to the app directory relative to the workspace |

**Results**

| Name | Description |
|---|---|
| `test-result` | `Pass` or `Fail` |

---

### `build-push-image`

Builds a container image using Buildah and pushes it to a registry.

**Params**

| Name | Default | Description |
|---|---|---|
| `image` | — | Full image name without tag |
| `tag` | `latest` | Image tag |
| `dockerfile` | `Dockerfile` | Path to Dockerfile within context |
| `context` | `app` | Build context path within workspace |
| `build-target` | `production` | Dockerfile multi-stage target |

**Results**

| Name | Description |
|---|---|
| `image-digest` | `sha256:...` digest of the pushed image |
| `image-url` | Full image URL including digest |

**Note:** Runs as `privileged: true` because Buildah requires it for `overlay` storage in Kubernetes.

---

### `update-image-tag`

Uses `sed` to update the image tag in the Helm values overlay file, then commits and pushes the change.

**Params**

| Name | Default | Description |
|---|---|---|
| `image-tag` | — | New tag to write |
| `environment` | `staging` | `staging` or `production` |
| `git-user-name` | `Tekton CI` | Git commit author name |
| `git-user-email` | `tekton@example.com` | Git commit author email |

The commit message includes `[skip ci]` to prevent triggering a new pipeline run from the same push.

---

## Pipeline — `sample-app-ci-cd`

The pipeline chains all four tasks:

```
clone-source ──▶ run-tests ──▶ build-push-image ──▶ update-image-tag
```

**Params**

| Name | Default | Description |
|---|---|---|
| `repo-url` | — | Source repository URL |
| `revision` | `main` | Git branch / SHA |
| `image` | `ghcr.io/example/sample-app` | Image name |
| `image-tag` | `latest` | Tag to build and push |
| `environment` | `staging` | Target environment |

**Workspaces**

| Name | Description |
|---|---|
| `shared-data` | PVC shared across all tasks |
| `registry-credentials` | Docker config secret |
| `git-credentials` | SSH key secret (optional) |

**Pipeline Results**

| Name | Source |
|---|---|
| `image-digest` | `build-push-image` task |
| `image-url` | `build-push-image` task |
| `commit` | `clone-source` task |

---

## Triggers

### EventListener

`tekton/triggers/eventlistener.yaml` creates an HTTP server (`el-github-webhook-listener`) in the `tekton-pipelines` namespace. GitHub sends push events to this service.

Two interceptors run in sequence:

1. **GitHub interceptor** — validates the HMAC signature using `github-webhook-secret`.
2. **CEL interceptor** — passes only pushes to `main` that are not `[skip ci]` commits.

### TriggerBinding

Extracts from the GitHub push payload:

| Binding param | Payload path |
|---|---|
| `repo-url` | `body.repository.clone_url` |
| `revision` | `body.after` (full SHA) |
| `branch` | `body.ref` |
| `image-tag` | `body.after[0:7]` (short SHA) |

### TriggerTemplate

Creates a `PipelineRun` with a `generateName` prefix (`sample-app-ci-cd-`), a `volumeClaimTemplate` PVC for the shared workspace, and wires in the registry and git credential secrets.

---

## Applying All Resources

```bash
kubectl apply -f tekton/tasks/
kubectl apply -f tekton/pipelines/
kubectl apply -f tekton/triggers/rbac.yaml
kubectl apply -f tekton/triggers/triggerbinding.yaml
kubectl apply -f tekton/triggers/triggertemplate.yaml
kubectl apply -f tekton/triggers/eventlistener.yaml
```

---

## Manual Pipeline Run

```bash
# Edit tekton/pipelineruns/manual-run.yaml to set the desired image-tag first
kubectl create -f tekton/pipelineruns/manual-run.yaml

# Stream logs
kubectl get pipelineruns -n tekton-pipelines -w

# Detailed task logs
tkn pipelinerun logs <pipelinerun-name> -n tekton-pipelines -f
```

---

## Watching Runs

```bash
# List recent PipelineRuns
tkn pipelinerun list -n tekton-pipelines

# Describe a specific run
tkn pipelinerun describe <name> -n tekton-pipelines

# List TaskRuns
tkn taskrun list -n tekton-pipelines
```

---

## RBAC

`tekton/triggers/rbac.yaml` creates:

- `ServiceAccount`: `tekton-triggers-sa`
- `Role` + `RoleBinding` in `tekton-pipelines` namespace
- `ClusterRole` + `ClusterRoleBinding` to allow PipelineRun creation cluster-wide

The EventListener Pod uses this ServiceAccount.

---

## Common Issues

| Problem | Cause | Fix |
|---|---|---|
| `build-push-image` fails with "permission denied" | Buildah needs privileged | Ensure `securityContext.privileged: true` is set on the step |
| `update-image-tag` push rejected | SSH key not in `known_hosts` | Add GitHub's key: `ssh-keyscan github.com >> known_hosts` |
| EventListener pod CrashLoopBackOff | RBAC missing | Reapply `triggers/rbac.yaml` |
| Webhook returns 403 | HMAC secret mismatch | Ensure `github-webhook-secret` matches the webhook secret in GitHub |
| PVC not deleted after run | VolumeClaimTemplate retention | Delete old PVCs with `kubectl delete pvc -n tekton-pipelines -l tekton.dev/pipeline=sample-app-ci-cd` |
