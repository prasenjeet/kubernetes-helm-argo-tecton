# kubernetes-helm-argo-tecton Wiki

Welcome to the project wiki. This repository is a production-ready reference for deploying a containerised application to Kubernetes using Helm for packaging, Argo CD or Harness CD for delivery, and Tekton for in-cluster CI.

## Pages

| Page | Summary |
|---|---|
| [Architecture](Architecture) | End-to-end diagrams for both CD paths |
| [Getting Started](Getting-Started) | Prerequisites and first-time setup |
| [Application](Application) | Flask app, endpoints, local development |
| [Helm Chart](Helm-Chart) | Chart structure and values reference |
| [Argo CD](Argo-CD) | GitOps setup, AppProject, Applications |
| [Tekton Pipelines](Tekton-Pipelines) | Tasks, Pipeline, Triggers reference |
| [Harness CD](Harness-CD) | Delegate, Connectors, Pipelines, Triggers |
| [Secrets Management](Secrets-Management) | How secrets are handled per tool |
| [Troubleshooting](Troubleshooting) | Common problems and fixes |

## Quick Links

- [Repository root](https://github.com/prasenjeet/kubernetes-helm-argo-tecton)
- [Helm chart](https://github.com/prasenjeet/kubernetes-helm-argo-tecton/tree/main/helm/sample-app)
- [Tekton pipeline](https://github.com/prasenjeet/kubernetes-helm-argo-tecton/tree/main/tekton/pipelines)
- [Harness CD pipeline](https://github.com/prasenjeet/kubernetes-helm-argo-tecton/tree/main/harness/pipelines)

## Tech Stack

| Component | Version / Notes |
|---|---|
| Python | 3.12 |
| Flask | 3.0 |
| Helm | 3.x |
| Argo CD | v2.11 |
| Tekton Pipelines | v0.59 |
| Tekton Triggers | v0.26 |
| Harness Delegate | 24.04 |
| Kubernetes | 1.27+ |

## CD Strategies at a Glance

### Argo CD (pull-based GitOps)
Argo CD continuously polls the Git repository and reconciles the cluster state. No external access to the cluster is required from CI — the cluster pulls changes.

### Harness CD (push-based with governance)
Harness CD pushes Helm releases to the cluster via the in-cluster Delegate. It adds human approval gates, audit trails, and built-in rollback without needing Argo CD.

Both paths share the same Helm chart and values files.
