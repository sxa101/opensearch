#!/bin/bash
set -euo pipefail

# install-opensearch-cluster.sh
# Deploy single-node OpenSearch cluster with JWT authentication and security hardening

NAMESPACE="opensearch"
JWT_SECRET="my-secret-jwt-key-for-opensearch-authentication-change-this-in-production"

echo "🔧 Installing OpenSearch Cluster in namespace: $NAMESPACE"

# Check if required tools are available
for tool in helm kubectl openssl; do
    if ! command -v "$tool" &> /dev/null; then
        echo "❌ Error: $tool is not installed or not in PATH"
        exit 1
    fi
done

# Ensure namespace exists
echo "📁 Ensuring namespace $NAMESPACE exists..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Label namespace for Istio injection
kubectl label namespace "$NAMESPACE" istio-injection=enabled --overwrite

echo "⚠️  Prerequisites check:"
echo "   - OpenSearch CRDs must be installed (run install-opensearch-crds.sh first)"
echo "   - OpenSearch Operator must be running (run install-opensearch-operator.sh first)"
echo "   - Istio must be installed in the cluster"

# Create JWT signing key secret
echo "🔐 Creating JWT signing key secret..."
kubectl create secret generic opensearch-jwt-secret \
    --from-literal=key="$JWT_SECRET" \
    --namespace "$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -

# Deploy OpenSearch Cluster using values file
echo "⚡ Deploying OpenSearch Cluster with security hardening..."
if [ -f "opensearch-cluster.yaml" ]; then
    kubectl apply -f opensearch-cluster.yaml --namespace "$NAMESPACE"
else
    echo "📝 Creating secure OpenSearch cluster manifest..."
    cat > opensearch-cluster-manifest.yaml <<EOF
apiVersion: opensearch.opster.io/v1
kind: OpenSearchCluster
metadata:
  name: opensearch-cluster
  namespace: $NAMESPACE
  annotations:
    sidecar.istio.io/inject: "true"
spec:
  general:
    httpPort: 9200
    version: "2.11.1"
    serviceName: opensearch-cluster
    serviceAccount: opensearch-cluster
    pluginsList: []
    vendor: opensearch
    drainDataTimeout: 300
  dashboards:
    version: "2.11.1"
    enable: true
    replicas: 1
    resources:
      requests:
        memory: "512Mi"
        cpu: "200m"
      limits:
        memory: "1Gi"
        cpu: "500m"
    additionalConfig:
      opensearch_security.auth.type: jwt
      opensearch_security.jwt.header: Authorization
      opensearch_security.jwt.url_parameter: ""
      opensearch_security.jwt.roles_key: roles
      opensearch_security.jwt.subject_key: sub
    securityContext:
      runAsNonRoot: true
      runAsUser: 1000
      runAsGroup: 1000
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: false
      seccompProfile:
        type: RuntimeDefault
      capabilities:
        drop:
          - ALL
        add:
          - CHOWN
          - DAC_OVERRIDE
          - SETGID
          - SETUID
  nodePools:
  - component: nodes
    replicas: 1
    diskSize: "5Gi"
    nodeClass: ""
    resources:
      requests:
        memory: "1Gi"
        cpu: "500m"
      limits:
        memory: "2Gi"
        cpu: "1000m"
    roles:
      - master
      - ingest
      - data
      - remote_cluster_client
    jvm: "-Xmx1g -Xms1g"
    additionalConfig:
      cluster.name: opensearch-cluster
      network.host: "0.0.0.0"
      plugins.security.ssl.http.enabled: false
      plugins.security.disabled: false
      plugins.security.allow_default_init_securityindex: true
      plugins.security.authcz.admin_dn:
        - "CN=admin,OU=SSL,O=Test,L=Test,C=DE"
      plugins.security.nodes_dn:
        - "CN=opensearch-cluster,OU=SSL,O=Test,L=Test,C=DE"
      plugins.security.audit.type: internal_opensearch
      plugins.security.enable_snapshot_restore_privilege: true
      plugins.security.check_snapshot_restore_write_privileges: true
      plugins.security.restapi.roles_enabled:
        - "all_access"
        - "security_rest_api_access"
      plugins.security.system_indices.enabled: true
      plugins.security.system_indices.indices:
        - ".plugins-ml-config"
        - ".plugins-ml-connector"
        - ".plugins-ml-model-group"
        - ".plugins-ml-model"
        - ".plugins-ml-task"
        - ".plugins-ml-conversation-meta"
        - ".plugins-ml-conversation-interactions"
        - ".plugins-ml-memory-meta"
        - ".plugins-ml-memory-message"
        - ".plugins-ml-stop-words"
        - ".opendistro-alerting-config"
        - ".opendistro-alerting-alert*"
        - ".opendistro-anomaly-results*"
        - ".opendistro-anomaly-detector*"
        - ".opendistro-anomaly-checkpoints"
        - ".opendistro-anomaly-detection-state"
        - ".opendistro-reports-*"
        - ".opensearch-notifications-*"
        - ".opensearch-notebooks"
        - ".opensearch-observability"
        - ".ql-datasources"
        - ".opendistro-asynchronous-search-response*"
        - ".replication-metadata-store"
        - ".opensearch-knn-models"
        - ".geospatial-ip2geo-data*"
        - ".plugins-flow-framework-config"
        - ".plugins-flow-framework-templates"
        - ".plugins-flow-framework-state"
      # JWT Authentication Configuration
      plugins.security.authc.jwt_auth_domain.http_enabled: true
      plugins.security.authc.jwt_auth_domain.transport_enabled: true
      plugins.security.authc.jwt_auth_domain.order: 0
      plugins.security.authc.jwt_auth_domain.http_authenticator.type: jwt
      plugins.security.authc.jwt_auth_domain.http_authenticator.challenge: false
      plugins.security.authc.jwt_auth_domain.http_authenticator.config.signing_key: "$JWT_SECRET"
      plugins.security.authc.jwt_auth_domain.http_authenticator.config.jwt_header: "Authorization"
      plugins.security.authc.jwt_auth_domain.http_authenticator.config.jwt_url_parameter: ""
      plugins.security.authc.jwt_auth_domain.http_authenticator.config.subject_key: "sub"
      plugins.security.authc.jwt_auth_domain.http_authenticator.config.roles_key: "roles"
      plugins.security.authc.jwt_auth_domain.authentication_backend.type: noop
    securityContext:
      runAsNonRoot: true
      runAsUser: 1000
      runAsGroup: 1000
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: false
      seccompProfile:
        type: RuntimeDefault
      capabilities:
        drop:
          - ALL
        add:
          - CHOWN
          - DAC_OVERRIDE
          - SETGID
          - SETUID
          - NET_BIND_SERVICE
    persistence:
      pvc:
        storageClass: standard
        accessModes:
        - ReadWriteOnce
EOF

    kubectl apply -f opensearch-cluster-manifest.yaml
fi

# Wait for cluster to be ready
echo "⏳ Waiting for OpenSearch cluster to be ready..."
kubectl wait --for=condition=Ready pod -l component=opensearch-cluster \
    --namespace "$NAMESPACE" --timeout=600s

echo "✅ OpenSearch Cluster deployment completed!"
echo "📋 Cluster Status:"
kubectl get opensearchcluster -n "$NAMESPACE"
echo ""
echo "🔒 JWT Authentication is enabled with shared secret"
echo "📝 Use generate-test-jwt.sh to create test tokens"
echo "🌐 Apply Istio manifests for external access"