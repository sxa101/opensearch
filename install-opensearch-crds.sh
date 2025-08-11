#!/bin/bash
set -euo pipefail

# install-opensearch-crds.sh
# This script performs the ONLY permitted cluster-level privileged action:
# Installing OpenSearch Custom Resource Definitions (CRDs) at the cluster level

echo "🔧 Installing OpenSearch CRDs - The only permitted cluster-level privileged operation"

# Check if required tools are available
for tool in helm kubectl; do
    if ! command -v "$tool" &> /dev/null; then
        echo "❌ Error: $tool is not installed or not in PATH"
        exit 1
    fi
done

# Add OpenSearch Helm repository if not already added
echo "📦 Adding OpenSearch Helm repository..."
helm repo add opensearch https://opensearch-project.github.io/helm-charts/ || echo "Repository already exists"
helm repo update

# Check if CRD files exist locally, otherwise use Helm
if [ -d "opensearch-operator/files" ] && [ -n "$(find opensearch-operator/files -name "*.yaml" -type f 2>/dev/null)" ]; then
    echo "🔍 Using local OpenSearch CRD files..."
    CRD_FILES=$(find opensearch-operator/files -name "*.yaml" -type f)
    
    echo "📋 Found local CRD files:"
    for file in $CRD_FILES; do
        echo "  - $(basename "$file")"
    done
    
    echo "⚡ Applying OpenSearch CRDs to cluster..."
    for crd_file in $CRD_FILES; do
        echo "Installing CRD: $(basename "$crd_file")"
        kubectl apply -f "$crd_file"
    done
else
    # Fallback to Helm extraction
    echo "🔍 Extracting OpenSearch CRDs from Helm chart..."
    
    # Create temporary directory for extracting CRDs
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT
    
    # Template the OpenSearch operator chart to extract CRDs
    helm template opensearch-operator opensearch/opensearch-operator \
        --version ">=2.0.0" \
        --output-dir "$TEMP_DIR" \
        --include-crds
    
    # Find and apply only CustomResourceDefinition manifests
    CRD_FILES=$(find "$TEMP_DIR" -name "*.yaml" -exec grep -l "kind: CustomResourceDefinition" {} \; 2>/dev/null || true)
    
    if [ -z "$CRD_FILES" ]; then
        echo "❌ No CRD files found in the Helm chart"
        exit 1
    fi
    
    echo "📋 Found CRD files:"
    echo "$CRD_FILES" | while read -r file; do
        echo "  - $(basename "$file")"
    done
    
    echo "⚡ Applying OpenSearch CRDs to cluster..."
    for crd_file in $CRD_FILES; do
        echo "Installing CRD: $(basename "$crd_file")"
        kubectl apply -f "$crd_file"
    done
fi

# Verify CRDs are installed
echo "✅ Verifying CRD installation..."
if kubectl get crd | grep -q opensearch; then
    echo "✅ OpenSearch CRDs successfully installed:"
    kubectl get crd | grep opensearch | while read -r line; do
        echo "  - $line"
    done
else
    echo "❌ OpenSearch CRDs installation failed"
    exit 1
fi

echo "🎉 OpenSearch CRDs installation completed successfully!"
echo "⚠️  This was the only permitted cluster-level privileged operation."
echo "📝 All subsequent operations will be namespace-scoped."