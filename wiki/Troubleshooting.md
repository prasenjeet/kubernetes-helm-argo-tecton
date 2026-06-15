# Troubleshooting

Quick reference for diagnosing problems across all components.

## General Diagnostics

```bash
# Check pod status across all project namespaces
kubectl get pods -n tekton-pipelines
kubectl get pods -n argocd
kubectl get pods -n harness-delegate-ng
kubectl get pods -n sample-app-staging
kubectl get pods -n sample-app-production

# Describe a pod (shows events and init errors)
kubectl describe pod <pod-name> -n <namespace>

# Check recent events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

---

## Application

### Pod stuck in `CrashLoopBackOff`

```bash
kubectl logs <pod-name> -n sample-app-staging
kubectl logs <pod-name> -n sample-app-staging --previous
```

Common causes:

| Symptom | Cause | Fix |
|---|---|---|
| `Permission denied` on `/tmp` | `readOnlyRootFilesystem: true` but no tmp volume | The `tmp` emptyDir volume is already in the Helm chart — check it is present |
| `Address already in use` | Port 8080 conflict | Only one container should listen on 8080; check the Deployment |
| Flask import error | Missing dependency | Ensure `requirements.txt` is complete and `pip install` ran |

### Pod in `ImagePullBackOff`

```bash
kubectl describe pod <pod-name> -n sample-app-staging | grep -A5 Events
```

Fixes:
- If registry is private: create `ghcr-pull-secret` and add to `imagePullSecrets` in values.
- If image tag does not exist: check that Tekton pushed it successfully.

---

## Helm

### `helm upgrade` fails with "manifest does not exist"

```bash
helm get manifest sample-app-staging -n sample-app-staging
```

Run `helm lint` locally to find template errors:

```bash
helm lint helm/sample-app/ -f helm/sample-app/values.yaml -f helm/sample-app/values-staging.yaml
```

### "release: not found" on `helm rollback`

The release has never been deployed. Run an initial `helm upgrade --install` first.

### Values not taking effect

Ensure you are passing all relevant files in order. Later files override earlier ones:

```bash
helm upgrade --install sample-app-staging helm/sample-app \
  -f helm/sample-app/values.yaml \
  -f helm/sample-app/values-staging.yaml \
  --set image.tag=abc1234
```

---

## Tekton

### EventListener not receiving webhooks

```bash
# Check EventListener pod logs
kubectl logs -l eventlistener=github-webhook-listener -n tekton-pipelines

# Verify the service is exposed
kubectl get svc -n tekton-pipelines | grep el-github
```

Confirm the GitHub webhook is delivering:  
GitHub → Repository → **Settings → Webhooks → Recent Deliveries** — check for `200` responses.

### Webhook returns `403 Forbidden`

The HMAC signature doesn't match. Ensure the `github-webhook-secret` Kubernetes Secret contains the exact same value as the webhook secret configured in GitHub.

```bash
kubectl get secret github-webhook-secret -n tekton-pipelines \
  -o jsonpath='{.data.secret}' | base64 -d
```

### PipelineRun never starts after push

```bash
# Check if the CEL filter is rejecting the payload
kubectl logs -l app=tekton-triggers-core-interceptors -n tekton-pipelines
```

The CEL filter passes only:
- `body.ref == 'refs/heads/main'`
- At least one commit in the payload
- Commit message does not contain `[skip ci]`

### `build-push-image` task fails

```bash
tkn taskrun logs <taskrun-name> -n tekton-pipelines -f
```

Common causes:

| Error | Fix |
|---|---|
| `unauthorized: unauthenticated` | Check `registry-credentials` secret and that it is mounted |
| `Error: error creating build container: ... permission denied` | Step must run `privileged: true` |
| `ERRO[0000] 'overlay' is not supported over overlayfs` | Use `vfs` storage driver, or use a bare-metal node |

### `update-image-tag` push fails

```bash
tkn taskrun logs <taskrun-name> -n tekton-pipelines
```

Common causes:

| Error | Fix |
|---|---|
| `Permission denied (publickey)` | Deploy key not added to the repository or wrong key in `git-ssh-credentials` |
| `Host key verification failed` | `known_hosts` file in the secret is stale; regenerate with `ssh-keyscan github.com` |
| `error: failed to push some refs` | The `revision` param doesn't match the branch — use `main` |

### PipelineRun workspace PVC pending

```bash
kubectl get pvc -n tekton-pipelines
```

If the PVC is stuck in `Pending`, the cluster has no `StorageClass` that can satisfy the claim. Install a default StorageClass or change the `accessModes` to match your cluster.

---

## Argo CD

### Application stuck in `OutOfSync`

```bash
argocd app get sample-app-staging
argocd app diff sample-app-staging
```

If Argo CD shows a diff but the cluster matches Git, the issue is usually a field that Helm sets dynamically (e.g., `resourceVersion`). Enable `--server-side-apply` or add a `diffing customization` in the Application spec.

### Sync loop (Argo CD keeps syncing)

Cause: `update-image-tag` commits without `[skip ci]`, which triggers Tekton, which commits again.

Fix: ensure the `update-image-tag` task always appends `[skip ci]` to the commit message (already done in the default task). Also ensure the Tekton CEL filter is in place.

### `ComparisonError: failed to build helm manifest`

```bash
argocd app get sample-app-staging --show-operation
```

Template error in the Helm chart. Run `helm template` locally:

```bash
helm template sample-app-staging helm/sample-app \
  -f helm/sample-app/values.yaml \
  -f helm/sample-app/values-staging.yaml
```

### Argo CD cannot pull from private repository

Add credentials:

```bash
argocd repo add https://github.com/example/kubernetes-helm-argo-tecton.git \
  --username <user> --password <pat>
```

---

## Harness CD

### Delegate not connecting

```bash
kubectl logs -l harness.io/name=sample-app-delegate -n harness-delegate-ng --tail=100
```

- Ensure egress to `app.harness.io:443` is not blocked.
- Verify `HARNESS_ACCOUNT_ID` is correct in the Deployment env.
- Check that `DELEGATE_TOKEN` in the `harness-delegate-account-token` Secret matches the token shown in the Harness UI.

### Pipeline stage fails with "No eligible delegates found"

The delegate selector in the connector or step doesn't match any registered delegate.

Check registered delegates: **Harness UI → Account Settings → Delegates**.

Ensure the delegate tag `sample-app-delegate` appears in the list and the delegate status is **Connected**.

### `HelmDeploy` step fails

In the Harness UI, open the failing execution, click the step, and expand **Console Output**.

Common causes:

| Error | Fix |
|---|---|
| `Error: UPGRADE FAILED: ... no objects visited` | The values file has a template error; test with `helm template` locally |
| `Error: context deadline exceeded` | Increase step timeout; default is 10 minutes |
| `Error: release ... has been abandoned` | Delete the failed release: `helm delete <release> -n <namespace>` |

### Approval step expired

The `HarnessApproval` step has a 1-day timeout. If it expires, the pipeline fails and the staging deploy remains live. Re-run the pipeline from Stage 3 (Deploy to Production) using **Re-run from Stage** in the UI, or trigger a new run.

### Artifact trigger not firing

1. Verify the GHCR connector can reach `ghcr.io` — test from the delegate pod:
   ```bash
   kubectl exec -it <delegate-pod> -n harness-delegate-ng -- \
     curl -s https://ghcr.io/v2/ -o /dev/null -w "%{http_code}"
   ```
2. Check the tag regex: `^(?!.*-rc).*$` excludes tags containing `-rc`. Test at [regex101.com](https://regex101.com).
3. In the Harness UI → Trigger → **Activity** tab, look for "No artifact change" messages.

---

## Checking What Is Deployed

```bash
# Which image tag is running in staging?
kubectl get deployment -n sample-app-staging \
  -o jsonpath='{.items[0].spec.template.spec.containers[0].image}'

# Helm release history
helm history sample-app-staging -n sample-app-staging
helm history sample-app-production -n sample-app-production
```
