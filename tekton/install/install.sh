#!/usr/bin/env bash
# Install Tekton Pipelines and Triggers
set -euo pipefail

TEKTON_PIPELINES_VERSION="v0.59.0"
TEKTON_TRIGGERS_VERSION="v0.26.2"
TEKTON_DASHBOARD_VERSION="v0.44.0"

echo "Installing Tekton Pipelines ${TEKTON_PIPELINES_VERSION}..."
kubectl apply -f "https://storage.googleapis.com/tekton-releases/pipeline/previous/${TEKTON_PIPELINES_VERSION}/release.yaml"

echo "Installing Tekton Triggers ${TEKTON_TRIGGERS_VERSION}..."
kubectl apply -f "https://storage.googleapis.com/tekton-releases/triggers/previous/${TEKTON_TRIGGERS_VERSION}/release.yaml"
kubectl apply -f "https://storage.googleapis.com/tekton-releases/triggers/previous/${TEKTON_TRIGGERS_VERSION}/interceptors.yaml"

echo "Installing Tekton Dashboard ${TEKTON_DASHBOARD_VERSION}..."
kubectl apply -f "https://storage.googleapis.com/tekton-releases/dashboard/previous/${TEKTON_DASHBOARD_VERSION}/release.yaml"

echo "Waiting for Tekton Pipelines to be ready..."
kubectl wait --for=condition=available --timeout=300s \
  deployment/tekton-pipelines-controller -n tekton-pipelines

echo "Waiting for Tekton Triggers to be ready..."
kubectl wait --for=condition=available --timeout=300s \
  deployment/tekton-triggers-controller -n tekton-pipelines

echo "Tekton installed successfully."
echo "Access the dashboard: kubectl port-forward svc/tekton-dashboard -n tekton-pipelines 9097:9097"
