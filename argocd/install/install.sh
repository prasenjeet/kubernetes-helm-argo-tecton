#!/usr/bin/env bash
# Install Argo CD into the argocd namespace
set -euo pipefail

ARGOCD_VERSION="v2.11.0"
NAMESPACE="argocd"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n "$NAMESPACE" \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "Waiting for Argo CD server to be ready..."
kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-server -n "$NAMESPACE"

echo "Argo CD installed successfully."
echo "Access the UI: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "Initial admin password: kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d"
