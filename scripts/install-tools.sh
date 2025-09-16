#!/bin/bash

# Scalable tool installation script for clusters repository
# Automatically installs missing tools based on operating system

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Operating system detection
OS=""
ARCH=""

detect_os() {
    case "$OSTYPE" in
        darwin*)  OS="macos" ;;
        linux*)   OS="linux" ;;
        msys*)    OS="windows" ;;
        *)        OS="unknown" ;;
    esac

    ARCH=$(uname -m)
    case $ARCH in
        x86_64|amd64) ARCH="amd64" ;;
        arm64|aarch64) ARCH="arm64" ;;
        armv7l) ARCH="arm" ;;
        *) echo -e "${RED}Unsupported architecture: $ARCH${NC}"; exit 1 ;;
    esac
}

# Installation functions for each tool
install_podman() {
    case $OS in
        "macos") brew install podman ;;
        "linux") curl -fsSL https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable/xUbuntu_22.04/Release.key | sudo gpg --dearmor -o /usr/share/keyrings/libcontainers-archive-keyring.gpg && echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/libcontainers-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable/xUbuntu_22.04/ /' | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list && sudo apt update && sudo apt install -y podman ;;
        *) return 1 ;;
    esac
}

install_helm() {
    case $OS in
        "macos") brew install helm ;;
        "linux") curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash ;;
        *) return 1 ;;
    esac
}

install_kubectl() {
    case $OS in
        "macos") brew install kubectl ;;
        "linux") curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl" && chmod +x kubectl && sudo mv kubectl /usr/local/bin/ ;;
        *) return 1 ;;
    esac
}

install_kind() {
    case $OS in
        "macos") brew install kind ;;
        "linux") curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-${ARCH} && chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind ;;
        *) return 1 ;;
    esac
}

install_flux() {
    case $OS in
        "macos") brew install fluxcd/tap/flux ;;
        "linux") curl -s https://fluxcd.io/install.sh | sudo bash ;;
        *) return 1 ;;
    esac
}

install_terraform() {
    case $OS in
        "macos") brew install terraform ;;
        "linux") curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add - && sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main" && sudo apt-get update && sudo apt-get install terraform ;;
        *) return 1 ;;
    esac
}

install_cdk() {
    case $OS in
        "macos") brew install --cask aws-cdk ;;
        "linux") npm install -g aws-cdk ;;
        *) return 1 ;;
    esac
}

install_kustomize() {
    case $OS in
        "macos") brew install kustomize ;;
        "linux") curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash && sudo mv kustomize /usr/local/bin/ ;;
        *) return 1 ;;
    esac
}

install_yq() {
    case $OS in
        "macos") brew install yq ;;
        "linux") sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${ARCH} && sudo chmod +x /usr/local/bin/yq ;;
        *) return 1 ;;
    esac
}


install_make() {
    case $OS in
        "macos") xcode-select --install ;;
        "linux") sudo apt update && sudo apt install -y build-essential ;;
        *) return 1 ;;
    esac
}

install_kubescape() {
    case $OS in
        "macos") brew install kubescape ;;
        "linux") curl -s https://raw.githubusercontent.com/kubescape/kubescape/master/install.sh | /bin/bash ;;
        *) return 1 ;;
    esac
}

install_trivy() {
    case $OS in
        "macos") brew install aquasecurity/trivy/trivy ;;
        "linux") curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin latest ;;
        *) return 1 ;;
    esac
}


install_trufflehog() {
    case $OS in
        "macos") brew install trufflehog ;;
        "linux")
            LATEST_URL=$(curl -s https://api.github.com/repos/trufflesecurity/trufflehog/releases/latest | grep browser_download_url | grep linux_${ARCH} | cut -d '"' -f 4)
            curl -Lo trufflehog.tar.gz "$LATEST_URL" && tar xzf trufflehog.tar.gz && sudo mv trufflehog /usr/local/bin/ && rm trufflehog.tar.gz
            ;;
        *) return 1 ;;
    esac
}


install_pluto() {
    case $OS in
        "macos") brew install FairwindsOps/tap/pluto ;;
        "linux")
            LATEST_URL=$(curl -s https://api.github.com/repos/FairwindsOps/pluto/releases/latest | grep browser_download_url | grep linux_${ARCH} | cut -d '"' -f 4)
            curl -Lo pluto.tar.gz "$LATEST_URL" && tar xzf pluto.tar.gz && sudo mv pluto /usr/local/bin/ && rm pluto.tar.gz
            ;;
        *) return 1 ;;
    esac
}


install_yamllint() {
    if command -v pip3 >/dev/null 2>&1; then
        pip3 install yamllint
    else
        echo -e "${RED}pip3 not found. Please install Python 3 and pip3 first.${NC}"
        return 1
    fi
}

# Installation dispatcher
install_tool() {
    local tool=$1
    echo -e "${BLUE}Installing $tool for $OS...${NC}"

    if command -v "install_${tool}" >/dev/null 2>&1; then
        if "install_${tool}"; then
            # Verify installation
            if command -v "$tool" >/dev/null 2>&1; then
                echo -e "${GREEN}✓ Successfully installed $tool${NC}"
                return 0
            else
                echo -e "${RED}✗ Failed to verify $tool installation${NC}"
                return 1
            fi
        else
            echo -e "${RED}✗ Failed to install $tool${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}⚠ No installation method defined for $tool${NC}"
        return 1
    fi
}

install_missing_tools() {
    local tools_to_install=("$@")
    local failed_installs=()

    echo -e "${BLUE}Starting installation of missing tools...${NC}"
    echo "========================================"

    for tool in "${tools_to_install[@]}"; do
        if ! install_tool "$tool"; then
            failed_installs+=("$tool")
        fi
        echo ""
    done

    if [ ${#failed_installs[@]} -eq 0 ]; then
        echo -e "${GREEN}All tools installed successfully!${NC}"
        return 0
    else
        echo -e "${RED}Failed to install the following tools:${NC}"
        printf "${RED}  - %s${NC}\n" "${failed_installs[@]}"
        echo ""
        echo -e "${YELLOW}Please install these tools manually or check the installation logs.${NC}"
        return 1
    fi
}

# Check for missing tools (reuse logic from check-tools.sh)
get_missing_tools() {
    local required_tools=(
        "podman" "helm" "kubectl" "kind" "flux" "terraform" "cdk"
        "kustomize" "yq" "make"
        "kubescape" "trivy" "trufflehog" "pluto" "yamllint"
    )

    local missing_tools=()

    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done

    echo "${missing_tools[@]}"
}

# Pre-installation checks
check_prerequisites() {
    echo -e "${BLUE}Checking prerequisites...${NC}"

    # Check for package managers
    case $OS in
        "macos")
            if ! command -v brew >/dev/null 2>&1; then
                echo -e "${YELLOW}Homebrew not found. Installing Homebrew first...${NC}"
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            fi
            ;;
        "linux")
            if ! command -v apt >/dev/null 2>&1 && ! command -v yum >/dev/null 2>&1; then
                echo -e "${RED}No supported package manager found (apt or yum)${NC}"
                exit 1
            fi

            # Check for pip3 for Python tools
            if ! command -v pip3 >/dev/null 2>&1; then
                echo -e "${YELLOW}pip3 not found. Installing python3-pip...${NC}"
                if command -v apt >/dev/null 2>&1; then
                    sudo apt update && sudo apt install -y python3-pip
                elif command -v yum >/dev/null 2>&1; then
                    sudo yum install -y python3-pip
                fi
            fi
            ;;
    esac
}

# Main execution
main() {
    echo -e "${GREEN}Scalable Tool Installation Script${NC}"
    echo "=================================="
    echo ""

    detect_os
    echo -e "${BLUE}Detected OS: $OS ($ARCH)${NC}"
    echo ""

    # Parse command line arguments
    case "${1:-}" in
        "--list"|"-l")
            echo "Available tools for installation:"
            for tool in podman helm kubectl kind flux terraform cdk kustomize yq make kubescape trivy trufflehog pluto yamllint; do
                echo "  - $tool"
            done
            exit 0
            ;;
        "--help"|"-h")
            echo "Usage: $0 [OPTIONS] [TOOLS...]"
            echo ""
            echo "Options:"
            echo "  --list, -l     List available tools"
            echo "  --help, -h     Show this help message"
            echo "  --all, -a      Install all missing tools"
            echo "  --scan-only    Install only Kubernetes scanning tools"
            echo ""
            echo "Examples:"
            echo "  $0 --all                    # Install all missing tools"
            echo "  $0 kubectl helm             # Install specific tools"
            echo "  $0 --scan-only              # Install only scanning tools"
            exit 0
            ;;
        "--all"|"-a")
            missing_tools_array=($(get_missing_tools))
            ;;
        "--scan-only")
            scan_tools=("kubescape" "trivy" "trufflehog" "pluto" "yamllint")
            missing_tools_array=()
            for tool in "${scan_tools[@]}"; do
                if ! command -v "$tool" >/dev/null 2>&1; then
                    missing_tools_array+=("$tool")
                fi
            done
            ;;
        "")
            # No arguments - show missing tools and ask what to do
            missing_tools_array=($(get_missing_tools))
            if [ ${#missing_tools_array[@]} -eq 0 ]; then
                echo -e "${GREEN}All tools are already installed!${NC}"
                exit 0
            else
                echo -e "${YELLOW}Missing tools detected:${NC}"
                printf "  - %s\n" "${missing_tools_array[@]}"
                echo ""
                echo "Run with --all to install all missing tools, or specify individual tools."
                echo "Use --help for more options."
                exit 1
            fi
            ;;
        *)
            # Specific tools requested
            missing_tools_array=("$@")
            ;;
    esac

    if [ ${#missing_tools_array[@]} -eq 0 ]; then
        echo -e "${GREEN}No tools to install.${NC}"
        exit 0
    fi

    echo -e "${YELLOW}Tools to install:${NC}"
    printf "  - %s\n" "${missing_tools_array[@]}"
    echo ""

    # Check prerequisites before installation
    check_prerequisites

    # Install tools
    install_missing_tools "${missing_tools_array[@]}"
}

# Run main function with all arguments
main "$@"