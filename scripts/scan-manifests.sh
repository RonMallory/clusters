#!/bin/bash

# Kubernetes Manifest Security Scanning Script
# Comprehensive security and best practice scanning for Kubernetes manifests

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_MANIFEST_DIR="platform/components"
DEFAULT_REPORTS_BASE="reports/manifest-scans"

# Script configuration
MANIFEST_DIR=""
REPORTS_DIR=""
TIMESTAMP=""
SCAN_SUMMARY=""
TOOLS_TO_RUN=()
VERBOSE=false

# Available scanning tools
AVAILABLE_TOOLS=("kubescape" "trivy" "pluto" "yamllint")

get_tool_description() {
    case $1 in
        "kubescape") echo "Comprehensive security posture assessment" ;;
        "trivy") echo "Vulnerability and misconfiguration scanning" ;;
        "pluto") echo "Deprecated API detection for upgrades" ;;
        "yamllint") echo "YAML syntax validation" ;;
        *) echo "Unknown tool" ;;
    esac
}

# Tool execution functions
run_kubescape() {
    if ! command -v kubescape >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ Kubescape not found, skipping...${NC}"
        return 0
    fi

    echo -e "${BLUE}Running Kubescape security scan...${NC}"
    kubescape scan "$MANIFEST_DIR" --format json --format-version v2 --output "$REPORTS_DIR/kubescape.json" 2>/dev/null || true
    kubescape scan "$MANIFEST_DIR" --format pretty-printer --output "$REPORTS_DIR/kubescape.txt" 2>/dev/null || true
    echo "✓ Kubescape report: kubescape.json & .txt" >> "$SCAN_SUMMARY"
    echo -e "${GREEN}✓ Kubescape report saved${NC}"
}

run_trivy() {
    if ! command -v trivy >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ Trivy not found, skipping...${NC}"
        return 0
    fi

    echo -e "${BLUE}Running Trivy configuration scan...${NC}"
    trivy config "$MANIFEST_DIR" --format json --output "$REPORTS_DIR/trivy.json" 2>/dev/null || true
    trivy config "$MANIFEST_DIR" --format table --output "$REPORTS_DIR/trivy.txt" 2>/dev/null || true
    echo "✓ Trivy report: trivy.json & .txt" >> "$SCAN_SUMMARY"
    echo -e "${GREEN}✓ Trivy report saved${NC}"
}

run_pluto() {
    if ! command -v pluto >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ Pluto not found, skipping...${NC}"
        return 0
    fi

    echo -e "${BLUE}Running Pluto deprecated API scan...${NC}"
    pluto detect-files -d "$MANIFEST_DIR" --output json > "$REPORTS_DIR/pluto.json" 2>&1 || true
    pluto detect-files -d "$MANIFEST_DIR" > "$REPORTS_DIR/pluto.txt" 2>&1 || true
    echo "✓ Pluto report: pluto.json & .txt" >> "$SCAN_SUMMARY"
    echo -e "${GREEN}✓ Pluto report saved${NC}"
}

run_yamllint() {
    if ! command -v yamllint >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ yamllint not found, skipping...${NC}"
        return 0
    fi

    echo -e "${BLUE}Running YAML syntax validation...${NC}"
    find "$MANIFEST_DIR" -name "*.yaml" -exec yamllint {} + > "$REPORTS_DIR/yamllint.txt" 2>&1 || echo "YAML validation completed" >> "$REPORTS_DIR/yamllint.txt"
    echo "✓ YAML lint report: yamllint.txt" >> "$SCAN_SUMMARY"
    echo -e "${GREEN}✓ YAML validation completed${NC}"
}

# Initialize scan session
init_scan() {
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    REPORTS_DIR="$DEFAULT_REPORTS_BASE/$TIMESTAMP"
    SCAN_SUMMARY="$REPORTS_DIR/scan-summary.txt"

    # Create reports directory
    mkdir -p "$REPORTS_DIR"

    # Initialize summary file
    cat > "$SCAN_SUMMARY" << EOF
Kubernetes Manifest Security Scan Report
Generated: $(date)
=========================================

Scan Configuration:
- Manifest Directory: $MANIFEST_DIR
- Reports Directory: $REPORTS_DIR
- Tools: $(IFS=', '; echo "${TOOLS_TO_RUN[*]}")

Scan Results:
EOF
}

# Finalize scan session
finalize_scan() {
    cat >> "$SCAN_SUMMARY" << EOF

Scan completed at: $(date)
EOF

    echo ""
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}Manifest scanning completed!${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo ""
    echo -e "${YELLOW}📁 Reports saved to: $REPORTS_DIR${NC}"
    echo -e "${YELLOW}📋 Summary: $REPORTS_DIR/scan-summary.txt${NC}"
    echo ""

    if [[ "$VERBOSE" == "true" ]]; then
        cat "$SCAN_SUMMARY"
    fi
}

# Print usage information
usage() {
    cat << EOF
Kubernetes Manifest Security Scanning Script

Usage: $0 [OPTIONS] [MANIFEST_DIR]

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Show scan summary at the end
    -t, --tools TOOLS       Comma-separated list of tools to run (default: all)
    -o, --output DIR        Base output directory (default: reports/manifest-scans)
    --list-tools            List available scanning tools

MANIFEST_DIR:
    Directory containing Kubernetes manifests to scan (default: platform/components)

AVAILABLE TOOLS:
EOF
    for tool in "${AVAILABLE_TOOLS[@]}"; do
        printf "    %-12s %s\n" "$tool" "$(get_tool_description "$tool")"
    done

    cat << EOF

EXAMPLES:
    $0                                          # Scan default directory with all tools
    $0 --tools kubescape,trivy                  # Run only specific tools
    $0 --verbose platform/apps                  # Scan specific directory with verbose output
    $0 --output /tmp/scans platform/components  # Custom output directory

EOF
}

# List available tools
list_tools() {
    echo "Available Scanning Tools:"
    echo "========================"
    for tool in "${AVAILABLE_TOOLS[@]}"; do
        status="❌ not installed"
        if command -v "$tool" >/dev/null 2>&1; then
            status="✅ installed"
        fi
        printf "%-12s %s - %s\n" "$tool" "$status" "$(get_tool_description "$tool")"
    done
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -t|--tools)
                IFS=',' read -ra TOOLS_TO_RUN <<< "$2"
                shift 2
                ;;
            -o|--output)
                DEFAULT_REPORTS_BASE="$2"
                shift 2
                ;;
            --list-tools)
                list_tools
                exit 0
                ;;
            -*)
                echo -e "${RED}Error: Unknown option $1${NC}" >&2
                usage >&2
                exit 1
                ;;
            *)
                if [[ -z "$MANIFEST_DIR" ]]; then
                    MANIFEST_DIR="$1"
                else
                    echo -e "${RED}Error: Too many arguments${NC}" >&2
                    usage >&2
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Set defaults
    if [[ -z "$MANIFEST_DIR" ]]; then
        MANIFEST_DIR="$DEFAULT_MANIFEST_DIR"
    fi

    if [[ ${#TOOLS_TO_RUN[@]} -eq 0 ]]; then
        TOOLS_TO_RUN=("${AVAILABLE_TOOLS[@]}")
    fi

    # Validate manifest directory
    if [[ ! -d "$MANIFEST_DIR" ]]; then
        echo -e "${RED}Error: Manifest directory '$MANIFEST_DIR' does not exist${NC}" >&2
        exit 1
    fi

    # Validate tools
    for tool in "${TOOLS_TO_RUN[@]}"; do
        if ! printf '%s\n' "${AVAILABLE_TOOLS[@]}" | grep -Fxq "$tool"; then
            echo -e "${RED}Error: Unknown tool '$tool'${NC}" >&2
            echo "Available tools: ${AVAILABLE_TOOLS[*]}" >&2
            exit 1
        fi
    done
}

# Main execution
main() {
    parse_args "$@"

    echo -e "${GREEN}Kubernetes Manifest Security Scanner${NC}"
    echo "===================================="
    echo ""

    init_scan

    echo -e "${BLUE}Scanning manifests in: $MANIFEST_DIR${NC}"
    echo -e "${BLUE}Reports will be saved to: $REPORTS_DIR${NC}"
    echo ""

    # Run selected tools
    for tool in "${TOOLS_TO_RUN[@]}"; do
        if command -v "run_$tool" >/dev/null 2>&1; then
            "run_$tool"
        else
            echo -e "${RED}Error: No handler for tool '$tool'${NC}" >&2
        fi
    done

    finalize_scan
}

# Run main function with all arguments
main "$@"
