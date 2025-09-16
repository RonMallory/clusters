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
    "podman"
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

echo ""
echo "Summary:"
echo "==============================="
printf "${GREEN}Found tools:${NC} %d/%d\n" "${#FOUND_TOOLS[@]}" "${#REQUIRED_TOOLS[@]}"

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
