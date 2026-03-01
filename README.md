# OpenClaw K8s Deployment

## Quick Start

### 1. Build & Push Image
```bash
cd openclaw-k8s
docker build --platform linux/amd64 -t registry.gitlab.com/gauvendi/infrastructure/openclaw:latest .
docker push registry.gitlab.com/gauvendi/infrastructure/openclaw:latest
```

### 2. Fill in Secrets
Edit `secret.yaml` — replace `REPLACE_ME` with your Anthropic API key.

### 3. Deploy
```bash
export KUBECONFIG=~/.ssh/netcup-cb-cluster.yaml
kubectl apply -f namespace.yaml
kubectl apply -f pvc.yaml
kubectl apply -f secret.yaml
kubectl apply -f slack-secret.yaml
kubectl apply -f configmap.yaml
kubectl apply -f serviceaccount.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
```

### 4. Migrate Workspace
```bash
# Copy current workspace into the PVC
POD=$(kubectl get pod -n openclaw -l app=openclaw -o jsonpath='{.items[0].metadata.name}')
kubectl cp ~/.openclaw/workspace $POD:/home/node/.openclaw/workspace -n openclaw
```

### 5. Verify
```bash
kubectl logs -n openclaw -l app=openclaw -f
```

## Architecture
- **OpenClaw container**: Gateway + Slack bot + agent runtime
- **DinD sidecar**: Docker-in-Docker for sandboxed agent sessions
- **PVC**: Persistent storage for workspace, sessions, memory
- **ServiceAccount**: cluster-admin for in-cluster kubectl access
- **Slack**: Socket mode (outbound only, no ingress needed)

## Notes
- Slack tokens are in `slack-secret.yaml` — rotate when needed
- ConfigMap mounts `openclaw.json` read-only; runtime changes go to PVC
- The Slack channel config references env vars for tokens, but OpenClaw
  also reads them from the config file. The env vars take precedence.
