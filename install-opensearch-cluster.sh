#!/bin/bash

# Strict Mode
set -euo pipefail

# Default values
NAMESPACE=""
KUBECONFIG=""
PROXY=""
ISTIO_INJECTION="disabled"

# --- Helper Functions ---

# Function to print usage information
usage() {
    echo "Usage: $0 --namespace <namespace> --kubeconfig <path-to-kubeconfig> [--proxy <proxy-url>] [--istio-injection <enabled|disabled>]"
    echo "  --namespace        : Kubernetes namespace to deploy to (required)"
    echo "  --kubeconfig       : Path to the kubeconfig file (required)"
    echo "  --proxy            : Optional proxy server URL"
    echo "  --istio-injection  : Optional: enable istio sidecar injection. Defaults to disabled"
    exit 1
}

# Function to log messages
log() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# --- Argument Parsing ---

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --namespace) NAMESPACE="$2"; shift ;;
        --kubeconfig) KUBECONFIG="$2"; shift ;;
        --proxy) PROXY="$2"; shift ;;
        --istio-injection) ISTIO_INJECTION="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

# Validate required arguments
if [ -z "$NAMESPACE" ] || [ -z "$KUBECONFIG" ]; then
    echo "Error: Missing required arguments."
    usage
fi

# --- Environment Setup ---

# Set Kubeconfig
export KUBECONFIG="$KUBECONFIG"

# Set Proxy if provided
if [ -n "$PROXY" ]; then
    export HTTPS_PROXY="$PROXY"
    log "Using proxy: $PROXY"
fi

# --- Installation ---

log "Starting OpenSearch Cluster installation in namespace: $NAMESPACE"

# 0. Create namespace if it doesn't exist
log "Ensuring namespace '$NAMESPACE' exists..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Prerequisite check reminder
log "IMPORTANT: This script assumes the OpenSearch Operator and Istio are already installed in your cluster."
log "IMPORTANT: The default StorageClass 'standard' is used. Ensure it exists or update the opensearch-cluster.yaml."

# 1. Create the opensearch-cluster.yaml from a template
log "Creating opensearch-cluster.yaml..."
cat > opensearch-cluster.yaml <<EOF
apiVersion: opensearch.opster.io/v1
kind: OpenSearchCluster
metadata:
  name: my-cluster
  namespace: $NAMESPACE
  annotations:
    "sidecar.istio.io/inject": "$ISTIO_INJECTION"
spec:
  general:
    version: 2.4.1
    serviceName: my-cluster
  nodePools:
  - component: master
    replicas: 1
    diskSize: "1Gi"
    persistence:
      pvc:
        storageClass: standard
        accessModes:
        - ReadWriteOnce
    roles:
      - master
    resources:
      requests:
        cpu: "1"
        memory: "1Gi"
      limits:
        cpu: "1"
        memory: "1Gi"
EOF

log "opensearch-cluster.yaml created successfully."

# 2. Apply the cluster manifest
log "Applying the OpenSearch cluster manifest..."
kubectl apply -f opensearch-cluster.yaml --namespace "$NAMESPACE"

# 3. Create Istio Gateway
log "Creating Istio Gateway..."
cat > istio-gateway.yaml <<EOF
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: opensearch-gateway
  namespace: $NAMESPACE
spec:
  selector:
    istio: ingressgateway # Use the default Istio ingress gateway
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    tls:
      mode: SIMPLE
      credentialName: opensearch-credential # IMPORTANT: You must create this secret with your TLS certificate!
    hosts:
    - "opensearch.$NAMESPACE.example.com"
EOF

kubectl apply -f istio-gateway.yaml --namespace "$NAMESPACE"

# 4. Create Istio VirtualService
log "Creating Istio VirtualService..."
cat > istio-virtualservice.yaml <<EOF
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: opensearch-vs
  namespace: $NAMESPACE
spec:
  hosts:
  - "opensearch.$NAMESPACE.example.com"
  gateways:
  - opensearch-gateway
  http:
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: my-cluster.$NAMESPACE.svc.cluster.local
        port:
          number: 9200
EOF

kubectl apply -f istio-virtualservice.yaml --namespace "$NAMESPACE"

# 5. Create Istio DestinationRule
log "Creating Istio DestinationRule..."
cat > istio-destinationrule.yaml <<EOF
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: opensearch-dr
  namespace: $NAMESPACE
spec:
  host: my-cluster.$NAMESPACE.svc.cluster.local
EOF

kubectl apply -f istio-destinationrule.yaml --namespace "$NAMESPACE"

# 6. Create Istio PeerAuthentication
log "Creating Istio PeerAuthentication policy..."
cat > istio-peerauth.yaml <<EOF
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: opensearch-peerauth
  namespace: $NAMESPACE
spec:
  selector:
    matchLabels:
      opensearch.opster.io/cluster-name: my-cluster
  mtls:
    mode: STRICT
EOF

kubectl apply -f istio-peerauth.yaml --namespace "$NAMESPACE"

log "OpenSearch Cluster installation complete."
log "The cluster will be provisioned by the OpenSearch Operator."
log "Monitor the status with: kubectl get opensearchcluster -n $NAMESPACE -w"
log "Istio Gateway, VirtualService, DestinationRule, and PeerAuthentication policy created for ingress and security."
log "To access OpenSearch from outside the cluster, ensure you have a secret named 'opensearch-credential' and have configured DNS for 'opensearch.$NAMESPACE.example.com' to point to your Istio Ingress Gateway."