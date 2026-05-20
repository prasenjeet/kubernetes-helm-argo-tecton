#!/usr/bin/env bash
# Install the Harness Kubernetes Delegate into the harness-delegate-ng namespace.
# Prerequisites: kubectl configured, HARNESS_ACCOUNT_ID and HARNESS_DELEGATE_TOKEN set.
set -euo pipefail

ACCOUNT_ID="${HARNESS_ACCOUNT_ID:?Set HARNESS_ACCOUNT_ID}"
DELEGATE_TOKEN="${HARNESS_DELEGATE_TOKEN:?Set HARNESS_DELEGATE_TOKEN}"
DELEGATE_NAME="${HARNESS_DELEGATE_NAME:-sample-app-delegate}"
MANAGER_HOST="https://app.harness.io"
NAMESPACE="harness-delegate-ng"
DELEGATE_IMAGE="harness/delegate:24.04.82601"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n "$NAMESPACE" -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: harness-serviceaccount
  namespace: ${NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: harness-delegate-cluster-admin
subjects:
  - kind: ServiceAccount
    name: harness-serviceaccount
    namespace: ${NAMESPACE}
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: v1
kind: Secret
metadata:
  name: harness-delegate-account-token
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  DELEGATE_TOKEN: "${DELEGATE_TOKEN}"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${DELEGATE_NAME}
  namespace: ${NAMESPACE}
  labels:
    harness.io/name: ${DELEGATE_NAME}
spec:
  replicas: 1
  selector:
    matchLabels:
      harness.io/name: ${DELEGATE_NAME}
  template:
    metadata:
      labels:
        harness.io/name: ${DELEGATE_NAME}
    spec:
      serviceAccountName: harness-serviceaccount
      terminationGracePeriodSeconds: 600
      restartPolicy: Always
      containers:
        - name: delegate
          image: ${DELEGATE_IMAGE}
          imagePullPolicy: Always
          securityContext:
            allowPrivilegeEscalation: false
            runAsUser: 0
          ports:
            - containerPort: 9090
          resources:
            requests:
              cpu: 0.5
              memory: 2Gi
            limits:
              cpu: 1
              memory: 4Gi
          livenessProbe:
            httpGet:
              path: /api/health
              port: 3460
              scheme: HTTP
            initialDelaySeconds: 10
            periodSeconds: 10
            failureThreshold: 3
          startupProbe:
            httpGet:
              path: /api/health
              port: 3460
              scheme: HTTP
            initialDelaySeconds: 30
            periodSeconds: 10
            failureThreshold: 15
          envFrom:
            - secretRef:
                name: harness-delegate-account-token
          env:
            - name: JAVA_OPTS
              value: "-Xms64m"
            - name: ACCOUNT_ID
              value: "${ACCOUNT_ID}"
            - name: MANAGER_HOST_AND_PORT
              value: "${MANAGER_HOST}"
            - name: DEPLOY_MODE
              value: KUBERNETES
            - name: DELEGATE_NAME
              value: "${DELEGATE_NAME}"
            - name: DELEGATE_TYPE
              value: KUBERNETES
            - name: DELEGATE_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
            - name: INIT_SCRIPT
              value: ""
            - name: DELEGATE_DESCRIPTION
              value: "Delegate for sample-app deployments"
            - name: DELEGATE_TAGS
              value: "k8s,sample-app"
            - name: NEXT_GEN
              value: "true"
            - name: CLIENT_TOOLS_DOWNLOAD_DISABLED
              value: "false"
            - name: LOG_STREAMING_SERVICE_URL
              value: "${MANAGER_HOST}/log-service/"
EOF

echo "Waiting for delegate pod to be ready..."
kubectl rollout status deployment/"${DELEGATE_NAME}" -n "$NAMESPACE" --timeout=300s

echo "Harness Delegate '${DELEGATE_NAME}' installed in namespace '${NAMESPACE}'."
echo "Verify registration at: ${MANAGER_HOST}/ng/#/account/${ACCOUNT_ID}/settings/delegates"
