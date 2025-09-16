#!/bin/bash
# Local Flux Development Setup
# Configures Flux to track local git repository for faster development

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Get current cluster name
get_cluster_info() {
    local current_context
    current_context=$(kubectl config current-context)

    if [[ "$current_context" =~ kind-(local-.+) ]]; then
        CLUSTER_NAME="${BASH_REMATCH[1]}"
        # Extract the git username from cluster name (local-username -> username)
        GIT_NAME_CLEAN="${CLUSTER_NAME#local-}"
        OVERLAY_DIR="$REPO_ROOT/clusters/local/overlay/$GIT_NAME_CLEAN"
        BOOTSTRAP_DIR="$REPO_ROOT/bootstrap/$CLUSTER_NAME"
    else
        echo "Error: Not in a personal cluster context. Run 'make apply-local' first."
        exit 1
    fi
}

# Setup local git tracking
setup_local_git_tracking() {
    log_info "Configuring Flux for local git tracking..."

    # Create local git repository configuration
    cat > "$BOOTSTRAP_DIR/git-repository-local.yaml" << EOF
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: flux-system-local
  namespace: flux-system
spec:
  interval: 10s                    # Check every 10 seconds for fast feedback
  ref:
    branch: $(git rev-parse --abbrev-ref HEAD)
  url: file://$REPO_ROOT           # Local filesystem path
  ignore: |
    # Ignore common files that don't affect deployments
    /.git/
    /scripts/
    /docs/
    /.github/
    /reports/
    /*.md
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: $CLUSTER_NAME-infrastructure-local
  namespace: flux-system
spec:
  interval: 30s                    # Quick reconciliation
  path: ./clusters/local/overlay/$GIT_NAME_CLEAN/infrastructure
  prune: true
  wait: true
  sourceRef:
    kind: GitRepository
    name: flux-system-local        # Use local git source
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: $CLUSTER_NAME-apps-local
  namespace: flux-system
spec:
  interval: 30s
  path: ./clusters/local/overlay/$GIT_NAME_CLEAN/apps
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system-local
  dependsOn:
    - name: $CLUSTER_NAME-infrastructure-local
EOF

    # Apply the local configuration
    kubectl apply -f "$BOOTSTRAP_DIR/git-repository-local.yaml"

    log_success "Flux now tracks local git repository!"
    echo ""
    echo "🚀 GitOps Development Workflow:"
    echo "1. Make changes to overlay configs in: clusters/local/overlay/$GIT_NAME_CLEAN/"
    echo "2. Commit locally: git add . && git commit -m 'your changes'"
    echo "3. Flux will sync automatically within 10-30 seconds"
    echo "4. No push required for testing - pure local GitOps!"
    echo "5. All deployments handled by Flux from Git commits"
}

# Setup filesystem watcher (alternative approach)
setup_filesystem_watcher() {
    log_info "Setting up filesystem watcher for immediate sync..."

    cat > "$BOOTSTRAP_DIR/local-dev-script.sh" << EOF
#!/bin/bash
# Filesystem watcher for immediate Flux sync

OVERLAY_DIR="./clusters/local/overlay/$GIT_NAME_CLEAN"

# Watch for changes and auto-commit
fswatch -o "\$OVERLAY_DIR" | while read f; do
    echo "Changes detected in \$OVERLAY_DIR"
    git add "\$OVERLAY_DIR"
    git commit -m "chore: auto-commit local changes for development" || true
    echo "Auto-committed changes, Flux will sync shortly..."
done
EOF

    chmod +x "$BOOTSTRAP_DIR/local-dev-script.sh"

    log_info "Filesystem watcher created. Run it with:"
    echo "  cd $REPO_ROOT && $BOOTSTRAP_DIR/local-dev-script.sh"
}

# Main function
main() {
    echo "🚀 Local Flux Development Setup"
    echo "================================"

    get_cluster_info

    echo "Select development mode:"
    echo "1) Local Git Tracking (file:// URL) - Requires git commits"
    echo "2) Filesystem Watcher - Auto-commits on file changes"
    echo "3) Both approaches"

    read -p "Choose [1-3]: " choice

    case $choice in
        1)
            setup_local_git_tracking
            ;;
        2)
            setup_filesystem_watcher
            ;;
        3)
            setup_local_git_tracking
            setup_filesystem_watcher
            ;;
        *)
            echo "Invalid choice"
            exit 1
            ;;
    esac

    echo ""
    echo "🎉 Local development setup complete!"
    echo ""
    echo "📋 Monitoring Commands:"
    echo "• Monitor Flux: flux get all"
    echo "• Watch logs: flux logs --follow"
    echo "• Check sources: flux get sources git"
    echo "• View kustomizations: flux get kustomizations"
    echo ""
    echo "🎯 Remember: All deployments are now managed by Flux from Git commits!"
    echo "✏️  Edit overlay files → commit → Flux auto-deploys"
}

main "$@"
