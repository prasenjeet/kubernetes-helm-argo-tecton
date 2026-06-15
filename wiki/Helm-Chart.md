# Helm Chart

The Helm chart at `helm/sample-app/` packages all Kubernetes resources for the application. Both Argo CD and Harness CD deploy the same chart using different values overlays.

## Chart Structure

```
helm/sample-app/
├── Chart.yaml                  Chart metadata and version
├── values.yaml                 Base values (production-safe defaults)
├── values-staging.yaml         Staging overrides
├── values-production.yaml      Production overrides
└── templates/
    ├── _helpers.tpl            Named template helpers
    ├── configmap.yaml          Environment variables ConfigMap
    ├── deployment.yaml         Deployment with probes and security context
    ├── service.yaml            ClusterIP Service
    ├── ingress.yaml            Optional Ingress (disabled by default)
    ├── serviceaccount.yaml     Dedicated ServiceAccount
    └── hpa.yaml                HorizontalPodAutoscaler (disabled by default)
```

## Values Reference

### Image

```yaml
image:
  repository: ghcr.io/example/sample-app   # Registry + image name
  pullPolicy: IfNotPresent
  tag: "1.0.0"                              # Overridden per environment
```

### Replicas and Scaling

```yaml
replicaCount: 2          # Ignored when autoscaling.enabled = true

autoscaling:
  enabled: false
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80
```

### Resources

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi
```

### Environment Variables

All keys under `env:` are written into a ConfigMap and mounted as environment variables in the container:

```yaml
env:
  ENVIRONMENT: production
  PORT: "8080"
  APP_VERSION: "1.0.0"    # Add any key here
```

### Probes

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 15
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 10
  failureThreshold: 3
```

### Ingress

```yaml
ingress:
  enabled: false          # Set true to create an Ingress
  className: nginx
  annotations: {}
  hosts:
    - host: sample-app.example.com
      paths:
        - path: /
          pathType: Prefix
  tls: []
```

### Security Context

```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000

securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: [ALL]
```

## Environment Overlays

### Staging (`values-staging.yaml`)

```yaml
replicaCount: 1
image:
  tag: latest
ingress:
  enabled: true
  hosts:
    - host: sample-app-staging.example.com
resources:
  requests: { cpu: 50m, memory: 64Mi }
  limits:   { cpu: 200m, memory: 128Mi }
env:
  ENVIRONMENT: staging
```

### Production (`values-production.yaml`)

```yaml
replicaCount: 3
image:
  tag: "1.0.0"
ingress:
  enabled: true
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    cert-manager.io/cluster-issuer: letsencrypt-prod
  tls:
    - secretName: sample-app-tls
      hosts: [sample-app.example.com]
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
env:
  ENVIRONMENT: production
```

## Deploying with Helm Directly

```bash
# Lint first
helm lint helm/sample-app/ -f helm/sample-app/values.yaml

# Dry-run (shows rendered manifests)
helm upgrade --install sample-app-staging helm/sample-app \
  -f helm/sample-app/values.yaml \
  -f helm/sample-app/values-staging.yaml \
  --namespace sample-app-staging \
  --create-namespace \
  --dry-run

# Deploy to staging
helm upgrade --install sample-app-staging helm/sample-app \
  -f helm/sample-app/values.yaml \
  -f helm/sample-app/values-staging.yaml \
  --namespace sample-app-staging \
  --create-namespace

# Deploy to production
helm upgrade --install sample-app-production helm/sample-app \
  -f helm/sample-app/values.yaml \
  -f helm/sample-app/values-production.yaml \
  --namespace sample-app-production \
  --create-namespace
```

## Overriding the Image Tag at Deploy Time

```bash
helm upgrade --install sample-app-staging helm/sample-app \
  -f helm/sample-app/values.yaml \
  -f helm/sample-app/values-staging.yaml \
  --set image.tag=abc1234 \
  --namespace sample-app-staging
```

## Checking Release History

```bash
helm history sample-app-staging -n sample-app-staging
```

## Rolling Back

```bash
# Roll back to the previous release
helm rollback sample-app-staging -n sample-app-staging

# Roll back to a specific revision
helm rollback sample-app-staging 3 -n sample-app-staging
```

## ConfigMap Checksum Annotation

The Deployment includes:

```yaml
annotations:
  checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
```

This forces a rolling restart whenever `env:` values change, even if the image tag has not changed.

## Adding a New Value

1. Add the key to `values.yaml` with a sensible default.
2. Reference it in the relevant template with `{{ .Values.<key> }}`.
3. Override per environment in `values-staging.yaml` or `values-production.yaml`.
4. If it is a secret, store the value in a Kubernetes Secret (outside the chart) and reference `secretKeyRef` in the Deployment template rather than putting it in the ConfigMap.
