#!/bin/bash

# Strict Mode
set -euo pipefail

# Default values
NAMESPACE=""
KUBECONFIG=""
PROXY=""

# --- Helper Functions ---

# Function to print usage information
usage() {
    echo "Usage: $0 --namespace <namespace> --kubeconfig <path-to-kubeconfig> [--proxy <proxy-url>]"
    echo "  --namespace      : Kubernetes namespace to deploy to (required)"
    echo "  --kubeconfig     : Path to the kubeconfig file (required)"
    echo "  --proxy          : Optional proxy server URL"
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

log "Starting OpenSearch Operator installation in namespace: $NAMESPACE"

# 1. Create namespace if it does not exist
log "Creating namespace $NAMESPACE if it does not exist..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# 2. Add OpenSearch Helm repository
log "Adding OpenSearch Helm repository..."
helm repo add opensearch-operator https://opensearch-project.github.io/opensearch-k8s-operator/
helm repo update

# 3. Render the Helm chart template
log "Rendering Helm chart to a local file..."
helm template opensearch-operator opensearch-operator/opensearch-operator \
    --namespace "$NAMESPACE" \
    --set manager.securityContext.seccompProfile.type=RuntimeDefault \
    --set manager.args[0]="--namespace=\$(NAMESPACE)" \
    > opensearch-operator.yaml

log "Successfully rendered Helm chart to opensearch-operator.yaml"


# 4. Use Python to transform ClusterRoles to Roles
log "Transforming ClusterRoles to Roles for namespace-scoping..."
python3 - "$NAMESPACE" <<'EOF'
import yaml
import sys

def transform_roles(file_path, namespace):
    with open(file_path, "r") as f:
        docs = list(yaml.safe_load_all(f))

    new_docs = []
    for doc in docs:
        if doc is None:
            continue
        
        kind = doc.get("kind")
        
        if kind == "ClusterRole":
            doc["kind"] = "Role"
            if "rules" in doc:
                new_rules = []
                for rule in doc["rules"]:
                    if "nonResourceURLs" not in rule:
                        new_rules.append(rule)
                doc["rules"] = new_rules
            if "metadata" in doc and "name" in doc["metadata"]:
                log(f"Transformed ClusterRole {doc['metadata']['name']} to Role")

        if kind == "ClusterRoleBinding":
            doc["kind"] = "RoleBinding"
            if "subjects" in doc:
                for subject in doc["subjects"]:
                    if "namespace" in subject:
                        subject["namespace"] = namespace
            if "roleRef" in doc and doc["roleRef"]["kind"] == "ClusterRole":
                doc["roleRef"]["kind"] = "Role"
                log(f"Transformed ClusterRoleBinding to RoleBinding")

        new_docs.append(doc)

    with open(file_path, "w") as f:
        yaml.dump_all(new_docs, f, default_flow_style=False, sort_keys=False)

def log(message):
    print(f"[PYTHON] {message}")

if __name__ == "__main__":
    transform_roles("opensearch-operator.yaml", sys.argv[1])
EOF

log "Successfully transformed roles."

# 5. Apply the modified manifest
log "Applying the modified manifest..."
kubectl apply -f opensearch-operator.yaml --namespace "$NAMESPACE"

log "OpenSearch Operator installation complete."
