#!/bin/bash

# Tool checking script for clusters repository
# Checks for required development and deployment tools

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Tools to check
REQUIRED_TOOLS=(
    "helm"
    "kubectl"
    "kind"
    "flux"
    "terraform"
    "cdk"
    "kustomize"
    "yq"
    "make"
    "kubescape"
    "trivy"
    "trufflehog"
    "pluto"
    "yamllint"
)

MISSING_TOOLS=()
FOUND_TOOLS=()

echo "Checking for required tools..."
echo "==============================="

# Function to get version for specific tools
get_tool_version() {
    local tool=$1
    case $tool in
        "helm")
            helm version --short 2>/dev/null | head -1 || helm version 2>/dev/null | grep Version | head -1 || echo "version unknown"
            ;;
        "kubectl")
            kubectl version --client 2>/dev/null | grep "Client Version" | head -1 || echo "version unknown"
            ;;
        "kustomize")
            kustomize version --short 2>/dev/null || kustomize version 2>/dev/null | head -1 || echo "version unknown"
            ;;
        "kubescape")
            kubescape version 2>/dev/null | head -1 || echo "version unknown"
            ;;
        "pluto")
            pluto version 2>/dev/null | head -1 || echo "version unknown"
            ;;
        "trivy")
            trivy --version 2>/dev/null | head -1 || echo "version unknown"
            ;;
        "flux")
            flux --version 2>/dev/null | head -1 || echo "version unknown"
            ;;
        *)
            # Default fallback for other tools
            $tool --version 2>/dev/null | head -1 || $tool -version 2>/dev/null | head -1 || $tool version 2>/dev/null | head -1 || echo "version unknown"
            ;;
    esac
}

# Check for container runtime (Docker or Podman)
check_container_runtime() {
    local runtime_found=false
    local runtime_info=""

    if command -v docker >/dev/null 2>&1; then
        if docker info >/dev/null 2>&1; then
            local docker_version=$(docker --version 2>/dev/null | head -1 || echo "version unknown")
            printf "${GREEN}✓${NC} %-12s %s\n" "docker" "$docker_version (running)"
            runtime_found=true
            runtime_info="docker (running)"
        else
            printf "${YELLOW}⚠${NC} %-12s %s\n" "docker" "installed but not running"
        fi
    fi

    if command -v podman >/dev/null 2>&1; then
        local podman_version=$(podman --version 2>/dev/null | head -1 || echo "version unknown")
        printf "${GREEN}✓${NC} %-12s %s\n" "podman" "$podman_version"
        runtime_found=true
        if [[ -z "$runtime_info" ]]; then
            runtime_info="podman"
        else
            runtime_info="$runtime_info, podman"
        fi
    fi

    if [[ "$runtime_found" == "true" ]]; then
        FOUND_TOOLS+=("container-runtime")
        return 0
    else
        printf "${RED}✗${NC} %-12s %s\n" "container-runtime" "neither docker nor podman found"
        MISSING_TOOLS+=("docker-or-podman")
        return 1
    fi
}

for tool in "${REQUIRED_TOOLS[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
        version=$(get_tool_version "$tool")
        printf "${GREEN}✓${NC} %-12s %s\n" "$tool" "$version"
        FOUND_TOOLS+=("$tool")
    else
        printf "${RED}✗${NC} %-12s %s\n" "$tool" "not found"
        MISSING_TOOLS+=("$tool")
    fi
done

# Check for container runtime
check_container_runtime

echo ""
echo "Summary:"
echo "==============================="
# Calculate total expected tools (required tools + container runtime)
total_expected=$((${#REQUIRED_TOOLS[@]} + 1))
printf "${GREEN}Found tools:${NC} %d/%d\n" "${#FOUND_TOOLS[@]}" "$total_expected"

if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
    printf "${RED}Missing tools:${NC} %s\n" "${MISSING_TOOLS[*]}"
    echo ""
    echo "Install missing tools before proceeding."
    echo "Refer to the documentation for installation instructions."
    exit 1
else
    printf "${GREEN}All required tools are installed!${NC}\n"
    exit 0
fi
