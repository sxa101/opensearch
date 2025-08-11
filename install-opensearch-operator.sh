#!/bin/bash
set -euo pipefail

# install-opensearch-operator.sh
# Deploy OpenSearch Operator with namespace-scoped permissions and security hardening

NAMESPACE="opensearch"

echo "🔧 Installing OpenSearch Operator in namespace: $NAMESPACE"

# Check if required tools are available
for tool in helm kubectl python3; do
    if ! command -v "$tool" &> /dev/null; then
        echo "❌ Error: $tool is not installed or not in PATH"
        exit 1
    fi
done

# Create namespace if it doesn't exist
echo "📁 Creating namespace $NAMESPACE if it doesn't exist..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Add OpenSearch Helm repository
echo "📦 Adding OpenSearch Helm repository..."
helm repo add opensearch https://opensearch-project.github.io/helm-charts/ || echo "Repository already exists"
helm repo update

# Install OpenSearch Operator using values file
echo "⚡ Installing OpenSearch Operator with security hardening..."
if [ -f "opensearch-operator.yaml" ]; then
    helm upgrade --install opensearch-operator opensearch-operator/opensearch-operator \
        --namespace "$NAMESPACE" \
        --values opensearch-operator.yaml \
        --wait \
        --timeout=10m
else
    echo "❌ opensearch-operator.yaml values file not found"
    echo "📝 Creating default secure values file..."
    
    # Create a minimal secure values file
    cat > opensearch-operator.yaml <<EOF
manager:
  image:
    tag: "2.4.1"
  replicas: 1
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    seccompProfile:
      type: RuntimeDefault
    capabilities:
      drop:
        - ALL
  podSecurityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault

# Convert cluster-level permissions to namespace-scoped
rbac:
  create: true
  clusterRole: false  # Disable cluster role creation
  rules:
    # Namespace-scoped permissions only
    - apiGroups: [""]
      resources: ["pods", "services", "configmaps", "secrets", "persistentvolumeclaims"]
      verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
    - apiGroups: ["apps"]
      resources: ["deployments", "statefulsets"]
      verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
    - apiGroups: ["opensearch.opster.io"]
      resources: ["opensearchclusters"]
      verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
EOF
    
    helm upgrade --install opensearch-operator opensearch-operator/opensearch-operator \
        --namespace "$NAMESPACE" \
        --values opensearch-operator.yaml \
        --wait \
        --timeout=10m
fi

# Create namespace-scoped RBAC if needed
echo "🔐 Creating namespace-scoped RBAC for OpenSearch Operator..."
cat > opensearch-operator-rbac.yaml <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: opensearch-operator
  namespace: $NAMESPACE
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: opensearch-operator
  namespace: $NAMESPACE
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "secrets", "persistentvolumeclaims", "endpoints"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets", "replicasets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["opensearch.opster.io"]
  resources: ["opensearchclusters", "opensearchclusters/status", "opensearchclusters/finalizers"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["policy"]
  resources: ["podsecuritypolicies"]
  verbs: ["use"]
- apiGroups: ["networking.k8s.io"]
  resources: ["networkpolicies"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: opensearch-operator
  namespace: $NAMESPACE
subjects:
- kind: ServiceAccount
  name: opensearch-operator
  namespace: $NAMESPACE
roleRef:
  kind: Role
  name: opensearch-operator
  apiGroup: rbac.authorization.k8s.io
EOF

kubectl apply -f opensearch-operator-rbac.yaml

# Verify installation
echo "✅ Verifying OpenSearch Operator installation..."
kubectl wait --for=condition=available deployment/opensearch-operator \
    --namespace "$NAMESPACE" --timeout=300s

if kubectl get deployment opensearch-operator -n "$NAMESPACE" | grep -q "1/1"; then
    echo "✅ OpenSearch Operator successfully installed and running!"
    echo "📋 Operator is running with namespace-scoped permissions only"
    echo "🔒 Security context enforced: non-root user, read-only filesystem, seccomp profile"
else
    echo "❌ OpenSearch Operator installation failed"
    echo "📝 Check logs: kubectl logs -n $NAMESPACE deployment/opensearch-operator"
    exit 1
fi

echo "🎉 OpenSearch Operator installation completed successfully!"
