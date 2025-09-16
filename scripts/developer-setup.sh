#!/bin/bash
# Developer Personal Cluster Setup Script
# Creates personalized local clusters, commits changes, and bootstraps Flux

set -euo pipefail

# Variables
SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KIND_CLUSTER_MANAGER="$SCRIPT_DIR/kind-cluster-manager.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Check prerequisites
check_prerequisites() {
    local missing_tools=()

    # Check required tools
    for tool in git kubectl kind flux kustomize; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Run 'make install-tools' to install missing dependencies"
        exit 1
    fi

    # Check if we're in a git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        log_error "This script must be run from within a git repository"
        exit 1
    fi
}

# Get git user information
get_git_info() {
    local git_name git_email git_branch

    git_name=$(git config user.name 2>/dev/null || echo "")
    git_email=$(git config user.email 2>/dev/null || echo "")
    git_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")

    if [[ -z "$git_name" ]] || [[ -z "$git_email" ]]; then
        log_error "Git user.name and user.email must be configured"
        log_info "Configure with: git config --global user.name 'Your Name'"
        log_info "Configure with: git config --global user.email 'you@example.com'"
        exit 1
    fi

    # Sanitize git name for cluster naming (remove spaces, special chars)
    GIT_NAME_CLEAN=$(echo "$git_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
    GIT_EMAIL="$git_email"
    GIT_BRANCH="$git_branch"
    CLUSTER_NAME="local-$GIT_NAME_CLEAN"
    PERSONAL_OVERLAY_DIR="$REPO_ROOT/clusters/local/overlay/$GIT_NAME_CLEAN"

    log_info "Git user: $git_name <$git_email>"
    log_info "Current branch: $GIT_BRANCH"
    log_info "Personal cluster name: $CLUSTER_NAME"
    log_info "Overlay directory: $PERSONAL_OVERLAY_DIR"
}

# Create personal overlay configuration
create_personal_cluster_config() {
    log_info "Creating personal cluster overlay configuration..."

    if [[ -d "$PERSONAL_OVERLAY_DIR" ]]; then
        log_warning "Personal overlay directory already exists: $PERSONAL_OVERLAY_DIR"
        log_info "Using existing configuration"
        return 0
    fi

    # Create overlay directory structure
    mkdir -p "$PERSONAL_OVERLAY_DIR/infrastructure"
    mkdir -p "$PERSONAL_OVERLAY_DIR/apps"

    # Create infrastructure overlay kustomization
    cat > "$PERSONAL_OVERLAY_DIR/infrastructure/kustomization.yaml" << EOF
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

metadata:
  name: $CLUSTER_NAME-infrastructure
  namespace: flux-system

# Base configuration from parent local cluster
resources:
  - ../../../infrastructure

# Optional: Add developer-specific customizations here
# patchesStrategicMerge:
#   - custom-patches.yaml
#
# resources:
#   - developer-specific-resources.yaml

EOF

    # Create apps overlay kustomization
    cat > "$PERSONAL_OVERLAY_DIR/apps/kustomization.yaml" << EOF
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

metadata:
  name: $CLUSTER_NAME-apps
  namespace: flux-system

# Base configuration from parent local cluster
resources:
  - ../../../apps

# Optional: Add developer-specific applications here
# resources:
#   - my-test-app.yaml
#
# patchesStrategicMerge:
#   - app-patches.yaml

EOF

    # Create a developer info file
    cat > "$PERSONAL_OVERLAY_DIR/README.md" << EOF
# Personal Development Overlay: $GIT_NAME_CLEAN

This overlay extends the base \`clusters/local/\` configuration with personal customizations.

## Details
- **Developer**: $GIT_EMAIL
- **Cluster**: $CLUSTER_NAME
- **Branch**: $GIT_BRANCH
- **Created**: $(date)

## Structure
- \`infrastructure/\` - Infrastructure overlay (cert-manager, CNPG, etc.)
- \`apps/\` - Applications overlay
- Both inherit from \`../../\` (base local cluster)

## Usage
\`\`\`bash
# Apply this overlay
kustomize build . | kubectl apply -f -

# Check what would be applied
kustomize build .
\`\`\`

## Customization
Add your personal resources, patches, or configuration changes to the respective kustomization.yaml files.
EOF

    log_success "Personal cluster overlay created: $PERSONAL_OVERLAY_DIR"
}

# Create and commit changes
commit_and_push_changes() {
    log_info "Committing and pushing personal cluster configuration..."

    # Add the new overlay directory including kind-config.yaml
    git add "$PERSONAL_OVERLAY_DIR/"

    # Check if there are changes to commit
    if git diff --cached --quiet; then
        log_info "No changes to commit"
        return 0
    fi

    # Create conventional commit message
    local commit_msg="feat(clusters): add personal overlay $GIT_NAME_CLEAN

- Create personal cluster overlay for $GIT_NAME_CLEAN
- Based on clusters/local/ with Kustomize overlay pattern
- Enables isolated development environment

Overlay: clusters/local/overlay/$GIT_NAME_CLEAN
Cluster: $CLUSTER_NAME
Branch: $GIT_BRANCH
User: $GIT_EMAIL"

    # Commit changes
    git commit -m "$commit_msg"

    # Push to current branch
    git push origin "$GIT_BRANCH"

    log_success "Changes committed and pushed to branch: $GIT_BRANCH"
}

# Create KIND cluster configuration
create_kind_config() {
    log_info "Creating KIND configuration for cluster: $CLUSTER_NAME..."

    local kind_config_file="$PERSONAL_OVERLAY_DIR/kind-config.yaml"

    # Skip if config already exists
    if [[ -f "$kind_config_file" ]]; then
        log_info "KIND config already exists: $kind_config_file"
        return 0
    fi

    cat > "$kind_config_file" << EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: $CLUSTER_NAME
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
        # Resource management for kubelet
        system-reserved: "cpu=200m,memory=512Mi"
        kube-reserved: "cpu=200m,memory=512Mi"
        eviction-hard: "memory.available<100Mi,nodefs.available<10%"
  - |
    kind: KubeletConfiguration
    # Kubelet resource configuration
    maxPods: 50  # Limit pods per node for resource control
    systemReserved:
      cpu: "200m"
      memory: "512Mi"
    kubeReserved:
      cpu: "200m"
      memory: "512Mi"
    enforceNodeAllocatable:
    - pods
    - system-reserved
    - kube-reserved
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
- role: worker
  kubeadmConfigPatches:
  - |
    kind: KubeletConfiguration
    # Worker node resource limits
    maxPods: 75
    systemReserved:
      cpu: "100m"
      memory: "256Mi"
    kubeReserved:
      cpu: "100m"
      memory: "256Mi"
    enforceNodeAllocatable:
    - pods
    - system-reserved
    - kube-reserved
EOF

    log_success "KIND config created: $kind_config_file"
}

# Create KIND cluster
create_kind_cluster() {
    log_info "Creating KIND cluster: $CLUSTER_NAME..."

    # Check if cluster already exists
    if kind get clusters 2>/dev/null | grep -q "^$CLUSTER_NAME$"; then
        log_warning "KIND cluster '$CLUSTER_NAME' already exists"
        log_info "Using existing cluster"
        return 0
    fi

    # Ensure KIND config exists
    create_kind_config

    # Create cluster using kind-cluster-manager with our config
    local kind_config_file="$PERSONAL_OVERLAY_DIR/kind-config.yaml"
    "$KIND_CLUSTER_MANAGER" create "$CLUSTER_NAME" --config "$kind_config_file"

    log_success "KIND cluster created: $CLUSTER_NAME"
}

# Bootstrap Flux
bootstrap_flux() {
    log_info "Bootstrapping Flux for personal cluster..."

    # Set kubectl context
    kubectl config use-context "kind-$CLUSTER_NAME"

    # Create bootstrap directory if it doesn't exist
    local bootstrap_dir="$REPO_ROOT/bootstrap/$CLUSTER_NAME"
    mkdir -p "$bootstrap_dir"

    # Generate and apply Flux installation
    local flux_bootstrap_file="$bootstrap_dir/flux-bootstrap.yaml"

    if [[ -f "$flux_bootstrap_file" ]]; then
        log_info "Using existing Flux bootstrap configuration"
        kubectl apply -f "$flux_bootstrap_file"
    else
        log_info "Generating new Flux bootstrap configuration"
        flux install --export > "$flux_bootstrap_file"
        kubectl apply -f "$flux_bootstrap_file"
    fi

    # Wait for Flux to be ready
    log_info "Waiting for Flux to be ready..."
    kubectl -n flux-system wait --for=condition=ready pod -l app=source-controller --timeout=300s
    kubectl -n flux-system wait --for=condition=ready pod -l app=kustomize-controller --timeout=300s

    # Create GitRepository resource for the current repository
    local git_repo_url git_repo_resource
    git_repo_url=$(git remote get-url origin)

    # Convert SSH URLs to HTTPS for Flux compatibility
    if [[ "$git_repo_url" =~ ^git@github\.com:(.+)\.git$ ]]; then
        git_repo_url="https://github.com/${BASH_REMATCH[1]}.git"
        log_info "Converted SSH URL to HTTPS for Flux: $git_repo_url"
    elif [[ "$git_repo_url" =~ ^git@(.+):(.+)\.git$ ]]; then
        git_repo_url="https://${BASH_REMATCH[1]}/${BASH_REMATCH[2]}.git"
        log_info "Converted SSH URL to HTTPS for Flux: $git_repo_url"
    fi

    cat > "$bootstrap_dir/git-repository.yaml" << EOF
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: flux-system
  namespace: flux-system
spec:
  interval: 1m
  ref:
    branch: $GIT_BRANCH
  url: $git_repo_url
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: $CLUSTER_NAME-infrastructure
  namespace: flux-system
spec:
  interval: 10m
  path: ./clusters/local/overlay/$GIT_NAME_CLEAN/infrastructure
  prune: true
  wait: true
  sourceRef:
    kind: GitRepository
    name: flux-system
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: $CLUSTER_NAME-apps
  namespace: flux-system
spec:
  interval: 10m
  path: ./clusters/local/overlay/$GIT_NAME_CLEAN/apps
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  dependsOn:
    - name: $CLUSTER_NAME-infrastructure
EOF

    # Apply GitRepository and Kustomizations
    kubectl apply -f "$bootstrap_dir/git-repository.yaml"

    log_success "Flux bootstrapped for cluster: $CLUSTER_NAME"
}

# Wait for Flux to apply configurations
wait_for_flux_sync() {
    log_info "Waiting for Flux to sync configurations from Git..."

    # Set kubectl context
    kubectl config use-context "kind-$CLUSTER_NAME"

    log_info "Flux will automatically apply configurations from: clusters/local/overlay/$GIT_NAME_CLEAN/"
    log_info "This follows GitOps principles - all deployments come from Git!"

    # Give Flux some time to discover and start applying resources
    log_info "Waiting 30 seconds for Flux to begin sync process..."
    sleep 30

    # Show Flux status
    log_info "Current Flux status:"
    if command -v flux >/dev/null 2>&1; then
        flux get sources git -A || true
        echo ""
        flux get kustomizations -A || true
    else
        kubectl get gitrepositories -n flux-system || true
        echo ""
        kubectl get kustomizations -n flux-system || true
    fi

    log_success "Flux is now managing your cluster from Git repository!"
}

# Show cluster status
show_status() {
    log_info "Personal cluster setup complete!"
    echo ""
    echo "Cluster Information:"
    echo "==================="
    echo "Cluster Name: $CLUSTER_NAME"
    echo "Git Branch: $GIT_BRANCH"
    echo "Git User: $GIT_EMAIL"
    echo "Overlay Directory: $PERSONAL_OVERLAY_DIR"
    echo "Bootstrap Directory: $REPO_ROOT/bootstrap/$CLUSTER_NAME"
    echo ""
    echo "Next Steps:"
    echo "==========="
    echo "1. Switch to your cluster context: kubectl config use-context kind-$CLUSTER_NAME"
    echo "2. Check Flux status: flux get all"
    echo "3. Monitor Flux logs: flux logs --follow"
    echo "4. Watch deployments: kubectl get all -A --watch"
    echo "5. Make changes to overlay files and push to git - Flux will auto-sync!"
    echo "6. Delete cluster when done: kind delete cluster --name $CLUSTER_NAME"
    echo ""
    echo "🎯 GitOps Active: All deployments are managed by Flux from your Git repository!"
    echo "📝 To customize: Edit files in $PERSONAL_OVERLAY_DIR and push to git"
}

# Help function
show_help() {
    cat << EOF
$SCRIPT_NAME - Developer Personal Cluster Setup

This script creates a personalized local Kubernetes cluster for development:
1. Creates a personal cluster configuration based on clusters/local/
2. Commits and pushes the configuration to the current git branch
3. Creates a KIND cluster named 'local-<git-username>'
4. Bootstraps Flux on the current branch
5. Applies the cluster configurations

USAGE:
    $SCRIPT_NAME [OPTIONS]

OPTIONS:
    -h, --help          Show this help message
    --no-commit         Skip git commit and push
    --no-flux           Skip Flux bootstrap
    --cluster-only      Only create the KIND cluster (skip config generation)

PREREQUISITES:
    - Git repository with user.name and user.email configured
    - Required tools: git, kubectl, kind, flux, kustomize

EXAMPLES:
    $SCRIPT_NAME                    # Full setup
    $SCRIPT_NAME --no-commit        # Skip git operations
    $SCRIPT_NAME --cluster-only     # Only create KIND cluster

EOF
}

# Parse command line arguments
parse_args() {
    SKIP_COMMIT=false
    SKIP_FLUX=false
    CLUSTER_ONLY=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            --no-commit)
                SKIP_COMMIT=true
                shift
                ;;
            --no-flux)
                SKIP_FLUX=true
                shift
                ;;
            --cluster-only)
                CLUSTER_ONLY=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Main function
main() {
    parse_args "$@"

    log_info "Starting developer personal cluster setup..."

    check_prerequisites
    get_git_info

    if [[ "$CLUSTER_ONLY" == "true" ]]; then
        # Even for cluster-only, we need the overlay directory structure for kind-config
        if [[ ! -d "$PERSONAL_OVERLAY_DIR" ]]; then
            log_info "Creating minimal overlay directory for KIND config..."
            mkdir -p "$PERSONAL_OVERLAY_DIR"
        fi
        create_kind_config
        create_kind_cluster
        show_status
        return 0
    fi

    create_personal_cluster_config
    create_kind_config

    if [[ "$SKIP_COMMIT" == "false" ]]; then
        commit_and_push_changes
    fi

    create_kind_cluster

    if [[ "$SKIP_FLUX" == "false" ]]; then
        bootstrap_flux
    fi

    wait_for_flux_sync
    show_status
}

# Run main function with all arguments
main "$@"
