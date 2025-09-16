#!/bin/bash

# TruffleHog Secret Scanning Script
# Comprehensive secret detection across git repositories and filesystems

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_TARGET="."
DEFAULT_REPORTS_BASE="reports/secret-scans"

# Script configuration
TARGET=""
REPORTS_DIR=""
TIMESTAMP=""
SCAN_SUMMARY=""
SCAN_MODES=()
VERBOSE=false
OUTPUT_FORMAT="json"

# Available scan modes
AVAILABLE_MODES=("git" "filesystem" "github" "docker")

get_mode_description() {
    case $1 in
        "git") echo "Scan git repository history for committed secrets" ;;
        "filesystem") echo "Scan filesystem for secrets in files" ;;
        "github") echo "Scan GitHub repository (requires GitHub token)" ;;
        "docker") echo "Scan Docker images for secrets" ;;
        *) echo "Unknown scan mode" ;;
    esac
}

# Scan execution functions
run_git_scan() {
    if ! command -v trufflehog >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ TruffleHog not found, skipping git scan...${NC}"
        return 0
    fi

    echo -e "${BLUE}Running TruffleHog git repository scan...${NC}"

    # Full scan with all findings
    trufflehog git "$TARGET" --json > "$REPORTS_DIR/git-all.json" 2>&1 || true

    # Verified secrets only
    trufflehog git "$TARGET" --only-verified --json > "$REPORTS_DIR/git-verified.json" 2>&1 || true

    # Human-readable format
    trufflehog git "$TARGET" --only-verified > "$REPORTS_DIR/git-verified.txt" 2>&1 || true
    trufflehog git "$TARGET" > "$REPORTS_DIR/git-all.txt" 2>&1 || true

    echo "✓ Git scan reports: git-all.json, git-verified.json, git-all.txt, git-verified.txt" >> "$SCAN_SUMMARY"
    echo -e "${GREEN}✓ Git repository scan completed${NC}"
}

run_filesystem_scan() {
    if ! command -v trufflehog >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ TruffleHog not found, skipping filesystem scan...${NC}"
        return 0
    fi

    echo -e "${BLUE}Running TruffleHog filesystem scan...${NC}"

    # Scan filesystem for secrets
    trufflehog filesystem "$TARGET" --json > "$REPORTS_DIR/filesystem-all.json" 2>&1 || true
    trufflehog filesystem "$TARGET" --only-verified --json > "$REPORTS_DIR/filesystem-verified.json" 2>&1 || true
    trufflehog filesystem "$TARGET" --only-verified > "$REPORTS_DIR/filesystem-verified.txt" 2>&1 || true
    trufflehog filesystem "$TARGET" > "$REPORTS_DIR/filesystem-all.txt" 2>&1 || true

    echo "✓ Filesystem scan reports: filesystem-all.json, filesystem-verified.json, filesystem-all.txt, filesystem-verified.txt" >> "$SCAN_SUMMARY"
    echo -e "${GREEN}✓ Filesystem scan completed${NC}"
}

run_github_scan() {
    if ! command -v trufflehog >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ TruffleHog not found, skipping GitHub scan...${NC}"
        return 0
    fi

    if [[ -z "$GITHUB_TOKEN" ]]; then
        echo -e "${YELLOW}⚠ GITHUB_TOKEN not set, skipping GitHub scan...${NC}"
        echo "⚠ GitHub scan skipped: No GITHUB_TOKEN environment variable" >> "$SCAN_SUMMARY"
        return 0
    fi

    echo -e "${BLUE}Running TruffleHog GitHub scan...${NC}"

    # GitHub repository scan (expects TARGET to be a GitHub repo URL or owner/repo)
    trufflehog github --repo "$TARGET" --json > "$REPORTS_DIR/github-all.json" 2>&1 || true
    trufflehog github --repo "$TARGET" --only-verified --json > "$REPORTS_DIR/github-verified.json" 2>&1 || true
    trufflehog github --repo "$TARGET" --only-verified > "$REPORTS_DIR/github-verified.txt" 2>&1 || true

    echo "✓ GitHub scan reports: github-all.json, github-verified.json, github-verified.txt" >> "$SCAN_SUMMARY"
    echo -e "${GREEN}✓ GitHub scan completed${NC}"
}

run_docker_scan() {
    if ! command -v trufflehog >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ TruffleHog not found, skipping Docker scan...${NC}"
        return 0
    fi

    echo -e "${BLUE}Running TruffleHog Docker image scan...${NC}"

    # Docker image scan (expects TARGET to be a Docker image name)
    trufflehog docker --image "$TARGET" --json > "$REPORTS_DIR/docker-all.json" 2>&1 || true
    trufflehog docker --image "$TARGET" --only-verified --json > "$REPORTS_DIR/docker-verified.json" 2>&1 || true
    trufflehog docker --image "$TARGET" --only-verified > "$REPORTS_DIR/docker-verified.txt" 2>&1 || true

    echo "✓ Docker scan reports: docker-all.json, docker-verified.json, docker-verified.txt" >> "$SCAN_SUMMARY"
    echo -e "${GREEN}✓ Docker scan completed${NC}"
}

# Additional secret scanning tools
run_git_secrets() {
    if ! command -v git >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ git not found, skipping git-secrets scan...${NC}"
        return 0
    fi

    echo -e "${BLUE}Running git-secrets scan...${NC}"

    if command -v git-secrets >/dev/null 2>&1; then
        git secrets --scan "$TARGET" > "$REPORTS_DIR/git-secrets.txt" 2>&1 || true
        echo "✓ git-secrets report: git-secrets.txt" >> "$SCAN_SUMMARY"
    else
        echo "git-secrets not installed, manual review recommended" > "$REPORTS_DIR/git-secrets.txt"
        echo "⚠ git-secrets not installed" >> "$SCAN_SUMMARY"
    fi

    echo -e "${GREEN}✓ git-secrets scan completed${NC}"
}

run_pattern_search() {
    echo -e "${BLUE}Running common secret pattern search...${NC}"

    # Search for common secret patterns in YAML and other config files
    grep -r -i -E "(password|secret|key|token|api[-_]?key|auth)" \
         --include="*.yaml" --include="*.yml" --include="*.json" --include="*.env" \
         --exclude-dir="reports" --exclude-dir=".git" \
         "$TARGET" | grep -v "secretName\|secretRef\|name:" > "$REPORTS_DIR/pattern-search.txt" 2>&1 || echo "No obvious secrets found in pattern search" > "$REPORTS_DIR/pattern-search.txt"

    echo "✓ Pattern search report: pattern-search.txt" >> "$SCAN_SUMMARY"
    echo -e "${GREEN}✓ Pattern search completed${NC}"
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
Secret Scanning Report
Generated: $(date)
======================

Scan Configuration:
- Target: $TARGET
- Reports Directory: $REPORTS_DIR
- Scan Modes: $(IFS=', '; echo "${SCAN_MODES[*]}")

Scan Results:
EOF
}

# Finalize scan session
finalize_scan() {
    # Generate summary statistics
    local verified_count=0
    local all_count=0

    if [[ -f "$REPORTS_DIR/git-verified.json" ]]; then
        verified_count=$(jq length "$REPORTS_DIR/git-verified.json" 2>/dev/null || echo 0)
    fi

    if [[ -f "$REPORTS_DIR/git-all.json" ]]; then
        all_count=$(jq length "$REPORTS_DIR/git-all.json" 2>/dev/null || echo 0)
    fi

    cat >> "$SCAN_SUMMARY" << EOF

Summary Statistics:
- Verified secrets found: $verified_count
- Total potential secrets: $all_count

Scan completed at: $(date)

Next Steps:
1. Review verified secrets immediately - these are high confidence findings
2. Investigate potential secrets in *-all.json files
3. Check pattern-search.txt for additional indicators
4. Consider adding findings to .gitignore or secret management system
EOF

    echo ""
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}Secret scanning completed!${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo ""
    echo -e "${YELLOW}📁 Reports saved to: $REPORTS_DIR${NC}"
    echo -e "${YELLOW}📋 Summary: $REPORTS_DIR/scan-summary.txt${NC}"

    if [[ $verified_count -gt 0 ]]; then
        echo -e "${RED}⚠️  WARNING: $verified_count verified secrets found!${NC}"
        echo -e "${RED}   Review $REPORTS_DIR/git-verified.txt immediately${NC}"
    fi

    echo ""

    if [[ "$VERBOSE" == "true" ]]; then
        cat "$SCAN_SUMMARY"
    fi
}

# Print usage information
usage() {
    cat << EOF
TruffleHog Secret Scanning Script

Usage: $0 [OPTIONS] [TARGET]

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Show scan summary at the end
    -m, --modes MODES       Comma-separated list of scan modes (default: git,filesystem)
    -o, --output DIR        Base output directory (default: reports/secret-scans)
    -f, --format FORMAT     Output format: json, yaml (default: json)
    --list-modes            List available scanning modes

TARGET:
    Target to scan (default: current directory)
    - For git mode: path to git repository
    - For filesystem mode: path to directory
    - For github mode: owner/repo or full GitHub URL
    - For docker mode: Docker image name

AVAILABLE MODES:
EOF
    for mode in "${AVAILABLE_MODES[@]}"; do
        printf "    %-12s %s\n" "$mode" "$(get_mode_description "$mode")"
    done

    cat << EOF

EXAMPLES:
    $0                                          # Scan current git repo + filesystem
    $0 --modes git                              # Git history scan only
    $0 --modes filesystem /path/to/code        # Filesystem scan of specific directory
    $0 --modes github owner/repo               # Scan GitHub repository
    $0 --modes docker nginx:latest             # Scan Docker image
    $0 --verbose --modes git,filesystem        # Full local scan with summary

ENVIRONMENT VARIABLES:
    GITHUB_TOKEN    GitHub personal access token (required for github mode)

EOF
}

# List available modes
list_modes() {
    echo "Available Secret Scanning Modes:"
    echo "================================"
    for mode in "${AVAILABLE_MODES[@]}"; do
        status="❌ TruffleHog required"
        if command -v trufflehog >/dev/null 2>&1; then
            case $mode in
                "github")
                    if [[ -n "$GITHUB_TOKEN" ]]; then
                        status="✅ ready"
                    else
                        status="⚠️  needs GITHUB_TOKEN"
                    fi
                    ;;
                *)
                    status="✅ ready"
                    ;;
            esac
        fi
        printf "%-12s %s - %s\n" "$mode" "$status" "$(get_mode_description "$mode")"
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
            -m|--modes)
                IFS=',' read -ra SCAN_MODES <<< "$2"
                shift 2
                ;;
            -o|--output)
                DEFAULT_REPORTS_BASE="$2"
                shift 2
                ;;
            -f|--format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --list-modes)
                list_modes
                exit 0
                ;;
            -*)
                echo -e "${RED}Error: Unknown option $1${NC}" >&2
                usage >&2
                exit 1
                ;;
            *)
                if [[ -z "$TARGET" ]]; then
                    TARGET="$1"
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
    if [[ -z "$TARGET" ]]; then
        TARGET="$DEFAULT_TARGET"
    fi

    if [[ ${#SCAN_MODES[@]} -eq 0 ]]; then
        SCAN_MODES=("git" "filesystem")
    fi

    # Validate modes
    for mode in "${SCAN_MODES[@]}"; do
        if ! printf '%s\n' "${AVAILABLE_MODES[@]}" | grep -Fxq "$mode"; then
            echo -e "${RED}Error: Unknown scan mode '$mode'${NC}" >&2
            echo "Available modes: ${AVAILABLE_MODES[*]}" >&2
            exit 1
        fi
    done

    # Validate target based on modes
    for mode in "${SCAN_MODES[@]}"; do
        case $mode in
            "git"|"filesystem")
                if [[ ! -e "$TARGET" ]]; then
                    echo -e "${RED}Error: Target '$TARGET' does not exist${NC}" >&2
                    exit 1
                fi
                ;;
            "github")
                if [[ -z "$GITHUB_TOKEN" ]]; then
                    echo -e "${YELLOW}Warning: GITHUB_TOKEN not set, GitHub scan will be skipped${NC}" >&2
                fi
                ;;
        esac
    done
}

# Main execution
main() {
    parse_args "$@"

    echo -e "${GREEN}TruffleHog Secret Scanner${NC}"
    echo "========================="
    echo ""

    init_scan

    echo -e "${BLUE}Scanning target: $TARGET${NC}"
    echo -e "${BLUE}Reports will be saved to: $REPORTS_DIR${NC}"
    echo ""

    # Run selected scan modes
    for mode in "${SCAN_MODES[@]}"; do
        case $mode in
            "git") run_git_scan ;;
            "filesystem") run_filesystem_scan ;;
            "github") run_github_scan ;;
            "docker") run_docker_scan ;;
        esac
    done

    # Always run additional scans
    run_git_secrets
    run_pattern_search

    finalize_scan
}

# Run main function with all arguments
main "$@"
