# Harness CD

Harness CD is the enterprise continuous delivery path. It uses the in-cluster Delegate agent to push Helm releases to Kubernetes and provides approval gates, audit trails, and built-in rollback.

## Concepts

| Concept | Description |
|---|---|
| **Delegate** | Lightweight agent inside the cluster; executes all pipeline steps |
| **Connector** | Authenticated connection to an external service (Git, registry, K8s) |
| **Service** | What you deploy — references the Helm chart source and container image |
| **Environment** | Where you deploy — staging or production, with typed variables |
| **Infrastructure** | How to connect to the K8s cluster for a given environment |
| **Pipeline** | Ordered stages: deploy, approval, deploy |
| **Trigger** | Fires the pipeline automatically (artifact change, webhook, schedule) |
| **Input Set** | Pre-filled parameter values for a pipeline run |

## Resource Layout

```
harness/
├── delegate/
│   └── install.sh                 Install the K8s Delegate
├── connectors/
│   ├── github-connector.yaml
│   ├── ghcr-connector.yaml
│   ├── kubernetes-staging-connector.yaml
│   └── kubernetes-production-connector.yaml
├── services/
│   └── sample-app.yaml            Helm source + GHCR artifact
├── environments/
│   ├── staging.yaml
│   └── production.yaml
├── infrastructure/
│   ├── staging-infra.yaml
│   └── production-infra.yaml
├── pipelines/
│   ├── cd-deploy-pipeline.yaml    Main 3-stage pipeline
│   └── rollback-pipeline.yaml     Emergency rollback
├── input-sets/
│   ├── staging-input-set.yaml
│   └── production-input-set.yaml
├── triggers/
│   ├── artifact-trigger.yaml      Fires on new GHCR image tag
│   └── webhook-trigger.yaml       Fires on GitHub push to main
└── secrets-reference.yaml         Required Harness secret identifiers
```

---

## Delegate

The Delegate runs as a Kubernetes `Deployment` in the `harness-delegate-ng` namespace. It connects outbound to `app.harness.io` and runs pipeline steps locally inside the cluster.

### Installation

```bash
export HARNESS_ACCOUNT_ID=<account-id>           # From Account Settings
export HARNESS_DELEGATE_TOKEN=<delegate-token>    # From Account Settings → Delegates
export HARNESS_DELEGATE_NAME=sample-app-delegate  # Optional, defaults to this value
bash harness/delegate/install.sh
```

### Resource Requirements

| Resource | Request | Limit |
|---|---|---|
| CPU | 0.5 | 1 |
| Memory | 2 Gi | 4 Gi |

### Verifying Registration

```bash
kubectl get pods -n harness-delegate-ng
```

In the Harness UI: **Account Settings → Delegates** — the delegate should appear with a green heartbeat within ~2 minutes of the Pod becoming ready.

### Delegate Tags

The delegate is tagged `k8s` and `sample-app`. Connectors and steps that specify `delegateSelectors: [sample-app-delegate]` will route to this delegate.

---

## Connectors

All connectors use `InheritFromDelegate` or secret references — no credentials are stored in the YAML files.

| Connector | Identifier | Type |
|---|---|---|
| GitHub | `GitHub` | GitHub HTTP (PAT) |
| GHCR Registry | `ghcr_registry` | Docker Registry |
| K8s Staging | `k8s_staging` | KubernetesCluster (InheritFromDelegate) |
| K8s Production | `k8s_production` | KubernetesCluster (InheritFromDelegate) |

---

## Service Definition

`harness/services/sample-app.yaml`

The service has two sources:

1. **Helm chart** — pulled from this repository at `helm/sample-app/` on the `main` branch via the `GitHub` connector.
2. **Container image** — pulled from `ghcr.io/example/sample-app` via the `ghcr_registry` connector. The tag is a runtime input (`<+input>`).

---

## Environments and Infrastructure

| Environment | Type | Namespace | Infra ID |
|---|---|---|---|
| `staging` | PreProduction | `sample-app-staging` | `staging_k8s` |
| `production` | Production | `sample-app-production` | `production_k8s` |

Both infrastructure definitions use `KubernetesDirect` with `InheritFromDelegate` so no static kubeconfig is needed.

The Helm release name is `release-<+INFRA_KEY_SHORT_ID>`, which generates a deterministic short identifier per environment.

---

## CD Deploy Pipeline

`harness/pipelines/cd-deploy-pipeline.yaml`

### Stages

```
Stage 1: Deploy to Staging
  ├─ HelmDeploy (values.yaml + values-staging.yaml, set image.tag + replicaCount)
  ├─ K8sRollingRollout (wait for rollout)
  └─ Http (GET /health → assert 200)

Stage 2: Approval to Promote          [timeout: 1 day]
  └─ HarnessApproval
       approvers: platform-team (min 1)
       approverInput: changeTicket

Stage 3: Deploy to Production
  ├─ HelmDeploy (values.yaml + values-production.yaml)
  ├─ K8sRollingRollout
  ├─ Http (GET /health → assert 200)
  └─ ShellScript (log image tag + change ticket)
```

Stages 2 and 3 only run if Stage 1 succeeds (`when: pipelineStatus: Success`).

### Automatic Rollback

Each deployment stage has `rollbackSteps`:

```yaml
rollbackSteps:
  - step:
      type: HelmRollback   # Reverts to the previous Helm revision on failure
```

### Running Manually

In the Harness UI: **CD → Pipelines → Deploy Sample App → Run Pipeline**

Set the `imageTag` runtime input to any existing tag (e.g., `abc1234`).

Via API:

```bash
curl -X POST \
  "https://app.harness.io/pipeline/api/pipeline/execute/Deploy_Sample_App?accountIdentifier=${HARNESS_ACCOUNT_ID}&orgIdentifier=default&projectIdentifier=sample_project" \
  -H "x-api-key: ${HARNESS_API_KEY}" \
  -H "Content-Type: application/yaml" \
  --data-binary @harness/input-sets/staging-input-set.yaml
```

---

## Rollback Pipeline

`harness/pipelines/rollback-pipeline.yaml`

An emergency pipeline that:

1. Requires an approval from `platform-team` (30-minute timeout).
2. Runs `helm rollback <release> 0` to revert to the previous revision.
3. Verifies the rollout with `kubectl rollout status`.

**Runtime input:** `targetEnvironment` — `staging` or `production`.

---

## Triggers

### Artifact Trigger

`harness/triggers/artifact-trigger.yaml`

Fires `Deploy_Sample_App` whenever a new image tag is pushed to `ghcr.io/example/sample-app`.

Exclusions:
- Tags matching `*-rc*` (release candidates) are excluded via `tagRegex: ^(?!.*-rc).*$`
- The `latest` floating tag is excluded via an event condition

### Webhook Trigger

`harness/triggers/webhook-trigger.yaml`

Fires `Deploy_Sample_App` on GitHub push to `main`. Uses a JEXL expression to skip `[skip ci]` commits. Sets `imageTag` to the first 7 characters of the commit SHA.

---

## Secrets Reference

All secret values are stored in the Harness Secret Manager, not in Git.

| Identifier | Used By |
|---|---|
| `github_username` | GitHub connector, GHCR connector |
| `github_pat_token` | GitHub connector, GHCR connector |
| `harness_delegate_token` | Delegate Deployment |
| `webhook_secret` | Webhook trigger HMAC validation |

Create in the Harness UI: **Account Settings → Secrets → + New Secret → Text**.

---

## Common Issues

| Problem | Cause | Fix |
|---|---|---|
| Delegate not appearing | Firewall blocking outbound to `app.harness.io` | Allow egress on port 443 from `harness-delegate-ng` namespace |
| `HelmDeploy` fails with "no release found" | First deploy, release doesn't exist | First run always creates the release; this is expected on initial deploy |
| Approval step timed out | No approver action within 1 day | Re-run the pipeline; the previous staging deploy is still live |
| Artifact trigger not firing | Tag regex not matching | Test the regex at regex101.com with sample tag strings |
| `Http` health check fails | App not yet ready | Increase `initialDelaySeconds` in the Helm values or add a wait step before the Http check |
