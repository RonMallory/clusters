#!/bin/bash
# KIND cluster management script
# Supports creating single or multiple local KIND clusters

set -euo pipefail

# Variables
SCRIPT_NAME=$(basename "$0")
KIND_PROVIDER="podman"
DEFAULT_CLUSTER_NAME="local-cluster"
CLUSTERS_DIR="$(dirname "$0")/../clusters/local"
KIND_CONFIG_FILE="${CLUSTERS_DIR}/kind-config.yaml"

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

# Help function
show_help() {
    cat << EOF
$SCRIPT_NAME - KIND cluster management

USAGE:
    $SCRIPT_NAME [COMMAND] [OPTIONS]

COMMANDS:
    create [NAME]           Create a single cluster (default: $DEFAULT_CLUSTER_NAME)
    create-multi NAMES      Create multiple clusters (space or comma separated)
    delete [NAME]           Delete a single cluster (default: $DEFAULT_CLUSTER_NAME)
    delete-multi NAMES      Delete multiple clusters
    delete-all              Delete all KIND clusters
    list                    List all KIND clusters
    status [NAME]           Show status of cluster(s)
    reset [NAME]            Delete and recreate cluster

OPTIONS:
    -c, --config FILE       Use specific KIND config file
    -w, --workers N         Number of worker nodes (default: 1)
    -p, --port-map PORT     Add port mapping (format: host:container)
    --no-wait              Don't wait for cluster to be ready
    -v, --verbose          Verbose output
    -h, --help             Show this help message

EXAMPLES:
    # Create single cluster with default name
    $SCRIPT_NAME create

    # Create cluster with custom name
    $SCRIPT_NAME create my-cluster

    # Create multiple clusters
    $SCRIPT_NAME create-multi "dev test staging"
    $SCRIPT_NAME create-multi "cluster1,cluster2,cluster3"

    # Create cluster with 3 worker nodes
    $SCRIPT_NAME create --workers 3

    # Create cluster with port mapping
    $SCRIPT_NAME create --port-map 8080:80

    # List all clusters
    $SCRIPT_NAME list

    # Delete specific cluster
    $SCRIPT_NAME delete my-cluster

    # Delete all clusters
    $SCRIPT_NAME delete-all

ENVIRONMENT:
    Uses $KIND_PROVIDER provider (automatically configured)

EOF
}

# Check prerequisites
check_prerequisites() {
    local missing_tools=()

    if ! command -v kind >/dev/null 2>&1; then
        missing_tools+=("kind")
    fi

    if ! command -v podman >/dev/null 2>&1; then
        missing_tools+=("podman")
    fi

    if ! command -v kubectl >/dev/null 2>&1; then
        missing_tools+=("kubectl")
    fi

    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install missing tools and try again"
        exit 1
    fi
}

# Generate KIND config
generate_kind_config() {
    local cluster_name="$1"
    local workers="${2:-1}"
    local port_mappings="${3:-}"
    local config_file="/tmp/kind-config-${cluster_name}.yaml"

    cat > "$config_file" << EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: $cluster_name
nodes:
- role: control-plane
EOF

    if [ -n "$port_mappings" ]; then
        echo "  extraPortMappings:" >> "$config_file"
        IFS=',' read -ra PORTS <<< "$port_mappings"
        for port in "${PORTS[@]}"; do
            if [[ "$port" =~ ^([0-9]+):([0-9]+)$ ]]; then
                host_port="${BASH_REMATCH[1]}"
                container_port="${BASH_REMATCH[2]}"
                cat >> "$config_file" << EOF
  - containerPort: $container_port
    hostPort: $host_port
    protocol: TCP
EOF
            fi
        done
    fi

    # Add worker nodes
    for ((i=1; i<=workers; i++)); do
        echo "- role: worker" >> "$config_file"
    done

    echo "$config_file"
}

# Create single cluster
create_cluster() {
    local cluster_name="${1:-$DEFAULT_CLUSTER_NAME}"
    local workers="${2:-1}"
    local port_mappings="${3:-}"
    local config_file="${4:-}"
    local no_wait="${5:-false}"

    log_info "Creating KIND cluster '$cluster_name'"

    # Check if cluster already exists
    if kind get clusters | grep -q "^$cluster_name$"; then
        log_warning "Cluster '$cluster_name' already exists"
        return 0
    fi

    # Set Podman as the provider
    export KIND_EXPERIMENTAL_PROVIDER="$KIND_PROVIDER"

    # Use provided config or generate one
    if [ -z "$config_file" ]; then
        config_file=$(generate_kind_config "$cluster_name" "$workers" "$port_mappings")
    elif [ ! -f "$config_file" ]; then
        log_error "Config file '$config_file' not found"
        return 1
    fi

    # Create the cluster
    log_info "Using config file: $config_file"
    if kind create cluster --config "$config_file"; then
        log_success "Cluster '$cluster_name' created successfully"

        # Wait for cluster to be ready unless --no-wait is specified
        if [ "$no_wait" != "true" ]; then
            log_info "Waiting for cluster to be ready..."
            kubectl wait --for=condition=Ready nodes --all --timeout=300s --context "kind-$cluster_name"
        fi

        # Show cluster info
        kubectl cluster-info --context "kind-$cluster_name"
    else
        log_error "Failed to create cluster '$cluster_name'"
        return 1
    fi

    # Clean up temporary config file
    if [[ "$config_file" == /tmp/kind-config-*.yaml ]]; then
        rm -f "$config_file"
    fi
}

# Create multiple clusters
create_multiple_clusters() {
    local cluster_names="$1"
    local workers="${2:-1}"
    local port_mappings="${3:-}"
    local no_wait="${4:-false}"

    # Parse cluster names (handle both comma and space separation)
    IFS=', ' read -ra NAMES <<< "$cluster_names"

    log_info "Creating ${#NAMES[@]} KIND clusters"

    local failed_clusters=()
    for name in "${NAMES[@]}"; do
        if [ -n "$name" ]; then
            log_info "Creating cluster: $name"
            if ! create_cluster "$name" "$workers" "$port_mappings" "" "$no_wait"; then
                failed_clusters+=("$name")
            fi
        fi
    done

    if [ ${#failed_clusters[@]} -ne 0 ]; then
        log_error "Failed to create clusters: ${failed_clusters[*]}"
        return 1
    fi

    log_success "All clusters created successfully"
}

# Delete single cluster
delete_cluster() {
    local cluster_name="${1:-$DEFAULT_CLUSTER_NAME}"

    if ! kind get clusters | grep -q "^$cluster_name$"; then
        log_warning "Cluster '$cluster_name' does not exist"
        return 0
    fi

    log_info "Deleting KIND cluster '$cluster_name'"
    if kind delete cluster --name "$cluster_name"; then
        log_success "Cluster '$cluster_name' deleted successfully"
    else
        log_error "Failed to delete cluster '$cluster_name'"
        return 1
    fi
}

# Delete multiple clusters
delete_multiple_clusters() {
    local cluster_names="$1"

    IFS=', ' read -ra NAMES <<< "$cluster_names"

    log_info "Deleting ${#NAMES[@]} KIND clusters"

    local failed_clusters=()
    for name in "${NAMES[@]}"; do
        if [ -n "$name" ]; then
            log_info "Deleting cluster: $name"
            if ! delete_cluster "$name"; then
                failed_clusters+=("$name")
            fi
        fi
    done

    if [ ${#failed_clusters[@]} -ne 0 ]; then
        log_error "Failed to delete clusters: ${failed_clusters[*]}"
        return 1
    fi

    log_success "All specified clusters deleted successfully"
}

# Delete all clusters
delete_all_clusters() {
    local clusters
    clusters=$(kind get clusters 2>/dev/null || true)

    if [ -z "$clusters" ]; then
        log_info "No KIND clusters found"
        return 0
    fi

    log_warning "This will delete ALL KIND clusters: $clusters"
    read -p "Are you sure? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Operation cancelled"
        return 0
    fi

    echo "$clusters" | while read -r cluster; do
        if [ -n "$cluster" ]; then
            delete_cluster "$cluster"
        fi
    done
}

# List clusters
list_clusters() {
    local clusters
    clusters=$(kind get clusters 2>/dev/null || true)

    if [ -z "$clusters" ]; then
        log_info "No KIND clusters found"
        return 0
    fi

    echo -e "${BLUE}KIND Clusters:${NC}"
    echo "================================"
    echo "$clusters" | while read -r cluster; do
        if [ -n "$cluster" ]; then
            # Get cluster status
            local status="Unknown"
            if kubectl cluster-info --context "kind-$cluster" >/dev/null 2>&1; then
                status="${GREEN}Running${NC}"
            else
                status="${RED}Not Ready${NC}"
            fi
            echo -e "  • $cluster - Status: $status"
        fi
    done
}

# Show cluster status
show_status() {
    local cluster_name="${1:-}"

    if [ -n "$cluster_name" ]; then
        # Show specific cluster status
        if ! kind get clusters | grep -q "^$cluster_name$"; then
            log_error "Cluster '$cluster_name' does not exist"
            return 1
        fi

        echo -e "${BLUE}Status for cluster '$cluster_name':${NC}"
        kubectl cluster-info --context "kind-$cluster_name"
        kubectl get nodes --context "kind-$cluster_name"
    else
        # Show all clusters status
        list_clusters
    fi
}

# Reset cluster (delete and recreate)
reset_cluster() {
    local cluster_name="${1:-$DEFAULT_CLUSTER_NAME}"
    local workers="${2:-1}"
    local port_mappings="${3:-}"
    local config_file="${4:-}"

    log_info "Resetting cluster '$cluster_name'"

    if kind get clusters | grep -q "^$cluster_name$"; then
        delete_cluster "$cluster_name"
    fi

    sleep 2
    create_cluster "$cluster_name" "$workers" "$port_mappings" "$config_file"
}

# Main script logic
main() {
    local command=""
    local config_file=""
    local workers="1"
    local port_mappings=""
    local no_wait=false
    local verbose=false

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                config_file="$2"
                shift 2
                ;;
            -w|--workers)
                workers="$2"
                shift 2
                ;;
            -p|--port-map)
                port_mappings="$2"
                shift 2
                ;;
            --no-wait)
                no_wait=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                set -x
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            create|create-multi|delete|delete-multi|delete-all|list|status|reset)
                command="$1"
                shift
                break
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Default command is create if none specified
    if [ -z "$command" ]; then
        command="create"
    fi

    # Check prerequisites
    check_prerequisites

    # Execute command
    case $command in
        create)
            create_cluster "${1:-$DEFAULT_CLUSTER_NAME}" "$workers" "$port_mappings" "$config_file" "$no_wait"
            ;;
        create-multi)
            if [ -z "$1" ]; then
                log_error "Please specify cluster names for create-multi"
                exit 1
            fi
            create_multiple_clusters "$1" "$workers" "$port_mappings" "$no_wait"
            ;;
        delete)
            delete_cluster "${1:-$DEFAULT_CLUSTER_NAME}"
            ;;
        delete-multi)
            if [ -z "$1" ]; then
                log_error "Please specify cluster names for delete-multi"
                exit 1
            fi
            delete_multiple_clusters "$1"
            ;;
        delete-all)
            delete_all_clusters
            ;;
        list)
            list_clusters
            ;;
        status)
            show_status "$1"
            ;;
        reset)
            reset_cluster "${1:-$DEFAULT_CLUSTER_NAME}" "$workers" "$port_mappings" "$config_file"
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"