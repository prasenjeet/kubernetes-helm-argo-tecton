# Architecture

## Overview

The project supports two independent continuous delivery paths that share the same application source code and Helm chart.

```
┌─────────────────────────────────────────────────────────────┐
│                        Developer                            │
│                    git push → main                          │
└──────────────────────────┬──────────────────────────────────┘
                           │
              ┌────────────┴────────────┐
              │                         │
              ▼                         ▼
   ┌─────────────────┐       ┌────────────────────┐
   │  Tekton CI      │       │  Harness Webhook   │
   │  (in-cluster)   │       │  Trigger           │
   └────────┬────────┘       └────────┬───────────┘
            │                         │
    build + test                  (waits for
    push image                    Tekton image)
            │                         │
            ▼                         │
   ┌─────────────────┐                │
   │  ghcr.io image  │◄───────────────┘
   │  (tagged SHA)   │
   └────────┬────────┘
            │
     ┌──────┴──────┐
     │             │
     ▼             ▼
 Path A         Path B
 Argo CD        Harness CD
 (GitOps)       (push + approval)
```

---

## Path A — Tekton CI + Argo CD

### Flow

```
git push → main
    │
    ▼
Tekton EventListener
(GitHub webhook, CEL filter: branch=main, no [skip ci])
    │
    ├─ Task 1: git-clone
    │     clone repo at commit SHA
    │
    ├─ Task 2: run-tests
    │     pytest in python:3.12-slim
    │
    ├─ Task 3: build-push-image
    │     buildah build → ghcr.io/example/sample-app:<sha>
    │
    └─ Task 4: update-image-tag
          sed values-staging.yaml image.tag = <sha>
          git commit + push "[skip ci]"
                    │
                    ▼
          Argo CD polls repo every 3 minutes
          detects diff in values-staging.yaml
                    │
                    ▼
          helm upgrade sample-app-staging
          (namespace: sample-app-staging)
                    │
                    ▼
          Production: manual sync in Argo CD UI
```

### Key Properties

| Property | Value |
|---|---|
| Cluster access | Pull (Argo CD agent inside cluster) |
| Staging sync | Automated (prune + self-heal) |
| Production sync | Manual approval in Argo CD UI |
| Rollback | `argocd app rollback` or sync to previous SHA |
| Audit trail | Git history + Argo CD sync history |

---

## Path B — Tekton CI + Harness CD

### Flow

```
git push → main
    │
    ├── Tekton CI (same as Path A up through image push)
    │       └─ image pushed to ghcr.io/example/sample-app:<sha>
    │
    └── Harness CD triggered by:
          • Artifact trigger (new GHCR tag detected)   OR
          • Webhook trigger (push to main)
                    │
          ┌─────────▼──────────────────────────────────┐
          │         cd-deploy-pipeline                  │
          │                                            │
          │  Stage 1: Deploy to Staging                │
          │    helm upgrade sample-app-staging         │
          │    HTTP health check /health               │
          │    (auto-rollback on failure)              │
          │                                            │
          │  Stage 2: HarnessApproval Gate             │
          │    platform-team reviews staging           │
          │    approver records change ticket          │
          │    timeout: 1 day                          │
          │                                            │
          │  Stage 3: Deploy to Production             │
          │    helm upgrade sample-app-production      │
          │    HTTP health check /health               │
          │    (auto-rollback on failure)              │
          └────────────────────────────────────────────┘
```

### Key Properties

| Property | Value |
|---|---|
| Cluster access | Push (Delegate agent inside cluster) |
| Staging deploy | Automatic after CI |
| Production deploy | Requires human approval |
| Rollback | Automatic (HelmRollback step) or manual via rollback pipeline |
| Audit trail | Harness execution history + approver logs |

---

## Namespace Layout

```
Kubernetes cluster
├── tekton-pipelines          Tekton controllers, EventListener, Tasks, Pipelines
├── harness-delegate-ng       Harness Delegate
├── argocd                    Argo CD server, repo-server, application-controller
├── sample-app-staging        Application workloads (staging)
└── sample-app-production     Application workloads (production)
```

---

## Component Interaction Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│ GitHub Repository                                                │
│  ├── app/         (Flask source)                                 │
│  ├── helm/        (Helm chart — shared by both CD paths)         │
│  ├── tekton/      (Pipeline + Trigger definitions)               │
│  ├── argocd/      (Argo CD Application + AppProject)             │
│  └── harness/     (Service, Pipeline, Trigger definitions)       │
└────────────────────────────┬─────────────────────────────────────┘
                             │
           ┌─────────────────┼──────────────────┐
           ▼                 ▼                  ▼
    Tekton Triggers    Argo CD           Harness Platform
    (EventListener)    (repo poll)       (artifact poll /
           │                │             webhook)
           ▼                │                  │
    Tekton Pipeline         │                  ▼
    (build/test/push)       │           Harness CD Pipeline
           │                │           (deploy + approve)
           ▼                ▼                  │
       ghcr.io         Git values file         │
       image           update ──────────────── ┘
                                               │
                              ┌────────────────┼────────────────┐
                              ▼                                 ▼
                    sample-app-staging              sample-app-production
                    (Kubernetes namespace)          (Kubernetes namespace)
```
