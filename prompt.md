---

You are an expert DevOps engineer tasked with producing a minimal, robust, and secure installation process for deploying an OpenSearch cluster and its operator into a **restricted Kubernetes namespace** (i.e., no cluster-wide privileges, no access to cluster roles or PSPs, etc.). Your task is to generate the **core install files** only.

---

### 📁 **Target Output Files**

You must generate **exactly** the following four files:

1. `install-opensearch-operator.sh` – Helm-based installation of the OpenSearch operator in a restricted namespace.
2. `install-opensearch-cluster.sh` – Helm-based installation of the OpenSearch cluster and configuration of Istio ingress.
3. `opensearch-operator.yaml` – Namespace-restricted Helm values or patches to ensure the operator works without cluster privileges.
4. `opensearch-cluster.yaml` – Helm values or configuration manifest for the OpenSearch cluster with:

   * JWT authentication enabled
   * Istio virtual service ingress
   * Istio destinate rule
   * Istio peer authorisation policy
   * Optional Istio sidecar injection toggle
   * Seccomp profile set to `RuntimeDefault` for all pods

---

### ⚙️ **System Constraints & Assumptions**

* CRDs are already pre-installed (no need to install or verify them).
* The Kubernetes namespace, kubeconfig, and proxy must be **parameterized via the command line** in both `.sh` scripts.
* No use of cluster-scoped roles, bindings, or privileged PSPs.
* All pods must run with the seccomp profile: `RuntimeDefault`.
* The scripts must be **idempotent** — they should not fail or create duplicates on re-run.
* The install process must **only use Helm and kubectl commands via Bash scripts**.
* Python may be used **to post-process Helm chart templates** (e.g., to rewrite `ClusterRole` into `Role`, patch RBACs to use Namespaced permissions, etc.).

---

### 🧠 **Behavioral Expectations**

* Refactor Helm values and manifests using Python to ensure all resources remain namespaced.
* Preserve maintainability: avoid hard-coding values; allow Helm overrides.
* Ensure all components are **non-privileged**, namespace-scoped, and enforce **least privilege**.
* Sidecar injection for Istio should be **optional**, ideally controlled by a Helm value or namespace label override.

---

### ✅ **Acceptance Criteria**

* All install steps are parameterized via command-line flags.
* Pods and containers are restricted per Kubernetes security best practices.
* OpenSearch cluster uses **JWT-based auth** (document how the JWT is configured).
* An **Istio VirtualService** is used to expose OpenSearch, defined in the cluster YAML.
* Final system should be **repeatable, cleanly installable, and uninstallable** with `kubectl delete`.

---

### 📎 **Input Examples for Scripts**

```bash
./install-opensearch-operator.sh \
  --namespace my-ns \
  --kubeconfig ~/.kube/config \
  --proxy https://my-k8s-api-proxy

./install-opensearch-cluster.sh \
  --namespace my-ns \
  --kubeconfig ~/.kube/config \
  --proxy https://my-k8s-api-proxy \
  --enable-sidecar-injection=false
```

---

### 🛠️ **Toolset Allowed**

* Bash (for installation logic, using `kubectl`, `helm`)
* Python (for mutating Helm templates, removing/rewriting cluster-wide roles)
* Helm (must be used to install both Operator and Cluster, not raw manifests)

---

### 📜 **Reminder**

Do not generate anything beyond the four core files listed. Each must be minimal yet complete and interdependent. Focus on **security**, **idempotency**, and **namespace restriction** above all.

---
