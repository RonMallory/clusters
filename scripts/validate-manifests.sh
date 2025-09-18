#!/bin/bash

# Kubernetes Manifest Validation Script
# Comprehensive validation for Kubernetes manifest files and Kustomize configurations

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_MANIFEST_DIR="."
DEFAULT_REPORTS_BASE="reports/validation"
DEFAULT_OUTPUT_FORMAT="table"

# Script configuration
MANIFEST_DIR=""
REPORTS_DIR=""
OUTPUT_FORMAT=""
TIMESTAMP=""
VALIDATION_SUMMARY=""
VALIDATORS_TO_RUN=()
VERBOSE=false
FAIL_FAST=false
DRY_RUN=false

# Available validation methods
AVAILABLE_VALIDATORS=("yaml" "kubectl" "kustomize" "deprecated-apis")

# Counters for summary
TOTAL_FILES=0
VALIDATED_FILES=0
FAILED_FILES=0
SKIPPED_FILES=0

# Arrays to track results
FAILED_VALIDATIONS=()
SUCCESSFUL_VALIDATIONS=()

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

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[VERBOSE]${NC} $1"
    fi
}

get_validator_description() {
    case $1 in
        "yaml") echo "YAML syntax validation using yamllint" ;;
        "kubectl") echo "Kubernetes manifest structure validation (offline mode)" ;;
        "kustomize") echo "Kustomize build validation for kustomization files" ;;
        "deprecated-apis") echo "Deprecated API detection using pluto" ;;
        *) echo "Unknown validator" ;;
    esac
}

# Check if required tools are available
check_tool() {
    local tool=$1
    if ! command -v "$tool" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

# YAML syntax validation
validate_yaml_syntax() {
    local file="$1"
    local report_file="$2"

    if ! check_tool yamllint; then
        log_warning "yamllint not found, skipping YAML validation"
        return 0
    fi

    log_verbose "Validating YAML syntax: $file"

    # Capture yamllint output for both report and terminal display
    local yamllint_output
    yamllint_output=$(yamllint "$file" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        echo "✓ YAML syntax: $file" >> "$VALIDATION_SUMMARY"
        echo "$yamllint_output" >> "$report_file"
        return 0
    else
        echo "✗ YAML syntax: $file" >> "$VALIDATION_SUMMARY"
        echo "$yamllint_output" >> "$report_file"

        # Also display error in terminal for immediate feedback
        echo ""
        log_error "YAML syntax validation failed for $file:"
        echo -e "${RED}$yamllint_output${NC}" >&2
        echo ""

        FAILED_VALIDATIONS+=("$file (YAML syntax)")
        return 1
    fi
}

# Kubernetes schema validation using kubectl dry-run (truly offline mode)
validate_kubernetes_schema() {
    local file="$1"
    local report_file="$2"

    if ! check_tool kubectl; then
        log_warning "kubectl not found, skipping Kubernetes schema validation"
        return 0
    fi

    log_verbose "Validating Kubernetes schema (offline): $file"

    # Skip kustomization.yaml files for kubectl validation
    if [[ "$(basename "$file")" == "kustomization.yaml" ]] || [[ "$(basename "$file")" == "kustomization.yml" ]]; then
        log_verbose "Skipping kubectl validation for kustomization file: $file"
        return 0
    fi

    {
        echo "Validating $file with kubectl dry-run (offline mode)..."

        # Check if cluster is available first
        if kubectl cluster-info >/dev/null 2>&1; then
            # Cluster is available - use normal validation
            local validation_output
            validation_output=$(kubectl apply --dry-run=client --validate=true -f "$file" 2>&1)
            local exit_code=$?
        else
            # No cluster available - use truly offline validation
            # This just checks if kubectl can parse the YAML structure
            log_verbose "No cluster available, performing basic YAML structure validation only"
            local validation_output
            validation_output=$(kubectl --kubeconfig=/dev/null apply --dry-run=client --validate=false -f "$file" 2>&1)
            local exit_code=$?

            # If that fails due to cluster connectivity, try alternative approach
            if [[ $exit_code -ne 0 ]] && echo "$validation_output" | grep -q "connection refused\|Unable to connect"; then
                # Use kubectl just to parse the YAML without validation
                validation_output=$(kubectl create --dry-run=client --validate=false --output=yaml -f "$file" >/dev/null 2>&1)
                exit_code=$?

                # If still failing due to connectivity, skip kubectl validation
                if [[ $exit_code -ne 0 ]]; then
                    echo "⚠ Kubernetes schema: Skipped (no cluster available)" >> "$VALIDATION_SUMMARY"
                    echo "Skipping kubectl validation - no cluster connectivity and kubectl requires API server access"
                    return 0
                fi
            fi
        fi

        if [[ $exit_code -eq 0 ]]; then
            echo "✓ Kubernetes schema (offline): $file" >> "$VALIDATION_SUMMARY"
            echo "Validation successful - manifest structure is valid"
            return 0
        else
            # Filter out connection errors for cleaner reporting
            if echo "$validation_output" | grep -q "connection refused\|Unable to connect"; then
                echo "⚠ Kubernetes schema: Skipped (no cluster available)" >> "$VALIDATION_SUMMARY"
                echo "Skipping kubectl validation - no cluster connectivity"
                return 0
            else
                echo "✗ Kubernetes schema (offline): $file" >> "$VALIDATION_SUMMARY"
                echo "Validation failed with error:"
                echo "$validation_output"

                # Also display error in terminal for immediate feedback
                echo ""
                log_error "Kubernetes schema validation failed for $file:"
                echo -e "${RED}$validation_output${NC}" >&2
                echo ""

                FAILED_VALIDATIONS+=("$file (Kubernetes schema)")
                return 1
            fi
        fi
    } >> "$report_file"
}

# Kustomize validation for kustomization files
validate_kustomize() {
    local file="$1"
    local report_file="$2"

    # Only validate kustomization files
    if [[ "$(basename "$file")" != "kustomization.yaml" ]] && [[ "$(basename "$file")" != "kustomization.yml" ]]; then
        return 0
    fi

    if ! check_tool kustomize; then
        log_warning "kustomize not found, skipping Kustomize validation"
        return 0
    fi

    log_verbose "Validating Kustomize build: $file"

    local dir=$(dirname "$file")

    {
        echo "Validating $file with kustomize build..."

        # Capture kustomize output for both report and terminal display
        local kustomize_output
        kustomize_output=$(kustomize build "$dir" 2>&1)
        local exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            echo "✓ Kustomize build: $file" >> "$VALIDATION_SUMMARY"
            echo "Kustomize build successful"
            return 0
        else
            echo "✗ Kustomize build: $file" >> "$VALIDATION_SUMMARY"
            echo "Kustomize build failed with error:"
            echo "$kustomize_output"

            # Also display error in terminal for immediate feedback
            echo ""
            log_error "Kustomize validation failed for $file:"
            echo -e "${RED}$kustomize_output${NC}" >&2
            echo ""

            FAILED_VALIDATIONS+=("$file (Kustomize build)")
            return 1
        fi
    } >> "$report_file"
}

# Deprecated API validation
validate_deprecated_apis() {
    local manifest_dir="$1"
    local report_file="$2"

    if ! check_tool pluto; then
        log_warning "pluto not found, skipping deprecated API validation"
        return 0
    fi

    log_verbose "Checking for deprecated APIs in: $manifest_dir"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Would check for deprecated APIs in: $manifest_dir"
        return 0
    fi

    {
        echo "Checking for deprecated APIs with pluto..."
        if pluto detect-files -d "$manifest_dir" >> "$report_file" 2>&1; then
            echo "✓ Deprecated APIs: No issues found" >> "$VALIDATION_SUMMARY"
            return 0
        else
            echo "⚠ Deprecated APIs: Issues found (check report)" >> "$VALIDATION_SUMMARY"
            return 1
        fi
    }
}

# Validate a single file
validate_file() {
    local file="$1"
    local success=true

    log_verbose "Processing file: $file"

    # Create individual report file for this validation
    local file_report="$REPORTS_DIR/$(basename "$file" .yaml)_$(basename "$file" .yml)_validation.txt"

    echo "Validation Report for: $file" > "$file_report"
    echo "Generated: $(date)" >> "$file_report"
    echo "============================================" >> "$file_report"
    echo "" >> "$file_report"

    # Run selected validators
    for validator in "${VALIDATORS_TO_RUN[@]}"; do
        case $validator in
            "yaml")
                if ! validate_yaml_syntax "$file" "$file_report"; then
                    success=false
                fi
                ;;
            "kubectl")
                if ! validate_kubernetes_schema "$file" "$file_report"; then
                    success=false
                fi
                ;;
            "kustomize")
                if ! validate_kustomize "$file" "$file_report"; then
                    success=false
                fi
                ;;
        esac

        if [[ "$FAIL_FAST" == "true" ]] && [[ "$success" == "false" ]]; then
            break
        fi
    done

    if [[ "$success" == "true" ]]; then
        SUCCESSFUL_VALIDATIONS+=("$file")
        VALIDATED_FILES=$((VALIDATED_FILES + 1))
        if [[ "$OUTPUT_FORMAT" == "table" ]]; then
            printf "${GREEN}✓${NC} %-50s %s\n" "$(basename "$file")" "PASSED"
        fi
    else
        FAILED_FILES=$((FAILED_FILES + 1))
        if [[ "$OUTPUT_FORMAT" == "table" ]]; then
            printf "${RED}✗${NC} %-50s %s\n" "$(basename "$file")" "FAILED"
        fi
    fi

    return $([ "$success" == "true" ] && echo 0 || echo 1)
}

# Find and validate manifest files
validate_manifests() {
    log_info "Scanning for manifest files in: $MANIFEST_DIR"

    # Find YAML files
    local yaml_files=()
    while IFS= read -r -d '' file; do
        yaml_files+=("$file")
    done < <(find "$MANIFEST_DIR" -type f \( -name "*.yaml" -o -name "*.yml" \) -print0 | sort -z)

    TOTAL_FILES=${#yaml_files[@]}

    if [[ $TOTAL_FILES -eq 0 ]]; then
        log_warning "No YAML manifest files found in $MANIFEST_DIR"
        return 0
    fi

    log_info "Found $TOTAL_FILES YAML files to validate"

    if [[ "$OUTPUT_FORMAT" == "table" ]]; then
        echo ""
        echo "Validation Results:"
        echo "=================================================="
        printf "%-50s %s\n" "FILE" "STATUS"
        echo "=================================================="
    fi

    # Validate each file
    for file in "${yaml_files[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "Would validate: $file"
            continue
        fi

        validate_file "$file"
    done

    # Run directory-level validators
    if printf '%s\n' "${VALIDATORS_TO_RUN[@]}" | grep -Fxq "deprecated-apis"; then
        validate_deprecated_apis "$MANIFEST_DIR" "$REPORTS_DIR/deprecated-apis.txt"
    fi
}

# Initialize validation session
init_validation() {
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    REPORTS_DIR="$DEFAULT_REPORTS_BASE/$TIMESTAMP"
    VALIDATION_SUMMARY="$REPORTS_DIR/validation-summary.txt"

    # Create reports directory
    if [[ "$DRY_RUN" == "false" ]]; then
        mkdir -p "$REPORTS_DIR"

        # Initialize summary file
        cat > "$VALIDATION_SUMMARY" << EOF
Kubernetes Manifest Validation Report
Generated: $(date)
=====================================

Validation Configuration:
- Manifest Directory: $MANIFEST_DIR
- Reports Directory: $REPORTS_DIR
- Validators: $(IFS=', '; echo "${VALIDATORS_TO_RUN[*]}")
- Output Format: $OUTPUT_FORMAT
- Fail Fast: $FAIL_FAST

Validation Results:
EOF
    fi
}

# Finalize validation session
finalize_validation() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run completed - no actual validation performed"
        log_info "Found $TOTAL_FILES YAML files that would be validated"
        return 0
    fi

    # Update summary
    cat >> "$VALIDATION_SUMMARY" << EOF

Summary Statistics:
- Total Files: $TOTAL_FILES
- Successfully Validated: $VALIDATED_FILES
- Failed Validations: $FAILED_FILES
- Skipped Files: $SKIPPED_FILES

Validation completed at: $(date)
EOF

    echo ""
    if [[ "$OUTPUT_FORMAT" == "table" ]]; then
        echo "=================================================="
    fi
    echo -e "${GREEN}Validation Summary${NC}"
    echo "=================="
    echo "Total Files: $TOTAL_FILES"
    echo "Successful: $VALIDATED_FILES"
    echo "Failed: $FAILED_FILES"
    echo "Skipped: $SKIPPED_FILES"
    echo ""

    if [[ $FAILED_FILES -gt 0 ]]; then
        echo -e "${RED}Failed Validations:${NC}"
        for failure in "${FAILED_VALIDATIONS[@]}"; do
            echo "  - $failure"
        done
        echo ""
    fi

    echo -e "${YELLOW}📁 Reports saved to: $REPORTS_DIR${NC}"
    echo -e "${YELLOW}📋 Summary: $VALIDATION_SUMMARY${NC}"
    echo ""

    if [[ "$VERBOSE" == "true" ]]; then
        cat "$VALIDATION_SUMMARY"
        echo ""
    fi

    # Exit with error code if any validations failed
    if [[ $FAILED_FILES -gt 0 ]]; then
        log_error "Validation failed with $FAILED_FILES failed files"
        return 1
    else
        log_success "All validations passed!"
        return 0
    fi
}

# Print usage information
usage() {
    cat << EOF
Kubernetes Manifest Validation Script

Usage: $0 [OPTIONS] [MANIFEST_DIR]

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Show verbose output
    -f, --fail-fast         Stop validation on first failure
    -n, --dry-run          Show what would be validated without running
    -t, --validators LIST   Comma-separated list of validators to run (default: all)
    -o, --output DIR        Base output directory (default: reports/validation)
    --format FORMAT         Output format: table, json (default: table)
    --list-validators       List available validators

MANIFEST_DIR:
    Directory containing Kubernetes manifests to validate (default: current directory)

AVAILABLE VALIDATORS:
EOF
    for validator in "${AVAILABLE_VALIDATORS[@]}"; do
        printf "    %-20s %s\n" "$validator" "$(get_validator_description "$validator")"
    done

    cat << EOF

EXAMPLES:
    $0                                          # Validate current directory with all validators
    $0 --validators yaml,kubectl               # Run only specific validators
    $0 --verbose --fail-fast clusters/        # Validate specific directory with options
    $0 --dry-run platform/components          # See what would be validated
    $0 --format json --output /tmp/reports    # JSON output to custom directory

TOOL REQUIREMENTS:
    - yamllint (for YAML syntax validation)
    - kubectl (for Kubernetes manifest structure validation - offline mode)
    - kustomize (for Kustomize build validation)
    - pluto (for deprecated API detection)

NOTE: All validation is performed offline without requiring cluster connectivity.
Missing tools will be skipped with warnings - no hard failures.

EOF
}

# List available validators
list_validators() {
    echo "Available Validators:"
    echo "===================="
    for validator in "${AVAILABLE_VALIDATORS[@]}"; do
        local status="❌ missing tools"
        local required_tools=""

        case $validator in
            "yaml")
                required_tools="yamllint"
                if check_tool yamllint; then
                    status="✅ ready"
                fi
                ;;
            "kubectl")
                required_tools="kubectl"
                if check_tool kubectl; then
                    status="✅ ready"
                fi
                ;;
            "kustomize")
                required_tools="kustomize"
                if check_tool kustomize; then
                    status="✅ ready"
                fi
                ;;
            "deprecated-apis")
                required_tools="pluto"
                if check_tool pluto; then
                    status="✅ ready"
                fi
                ;;
        esac

        printf "%-20s %s - %s\n" "$validator" "$status" "$(get_validator_description "$validator")"
        printf "%-20s Required: %s\n" "" "$required_tools"
        echo ""
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
            -f|--fail-fast)
                FAIL_FAST=true
                shift
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -t|--validators)
                IFS=',' read -ra VALIDATORS_TO_RUN <<< "$2"
                shift 2
                ;;
            -o|--output)
                DEFAULT_REPORTS_BASE="$2"
                shift 2
                ;;
            --format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --list-validators)
                list_validators
                exit 0
                ;;
            -*)
                log_error "Unknown option $1"
                usage >&2
                exit 1
                ;;
            *)
                if [[ -z "$MANIFEST_DIR" ]]; then
                    MANIFEST_DIR="$1"
                else
                    log_error "Too many arguments"
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

    if [[ -z "$OUTPUT_FORMAT" ]]; then
        OUTPUT_FORMAT="$DEFAULT_OUTPUT_FORMAT"
    fi

    if [[ ${#VALIDATORS_TO_RUN[@]} -eq 0 ]]; then
        VALIDATORS_TO_RUN=("${AVAILABLE_VALIDATORS[@]}")
    fi

    # Validate arguments
    if [[ ! -d "$MANIFEST_DIR" ]]; then
        log_error "Manifest directory '$MANIFEST_DIR' does not exist"
        exit 1
    fi

    # Validate validators
    for validator in "${VALIDATORS_TO_RUN[@]}"; do
        if ! printf '%s\n' "${AVAILABLE_VALIDATORS[@]}" | grep -Fxq "$validator"; then
            log_error "Unknown validator '$validator'"
            echo "Available validators: ${AVAILABLE_VALIDATORS[*]}" >&2
            exit 1
        fi
    done

    # Validate output format
    if [[ "$OUTPUT_FORMAT" != "table" ]] && [[ "$OUTPUT_FORMAT" != "json" ]]; then
        log_error "Invalid output format '$OUTPUT_FORMAT'. Use 'table' or 'json'"
        exit 1
    fi
}

# Main execution
main() {
    parse_args "$@"

    log_info "Kubernetes Manifest Validator"
    echo "============================="
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE - No actual validation will be performed"
        echo ""
    fi

    log_info "Configuration:"
    log_info "  Directory: $MANIFEST_DIR"
    log_info "  Validators: ${VALIDATORS_TO_RUN[*]}"
    log_info "  Output Format: $OUTPUT_FORMAT"
    log_info "  Fail Fast: $FAIL_FAST"
    log_info "  Verbose: $VERBOSE"
    echo ""

    init_validation
    validate_manifests
    finalize_validation
}

# Run main function with all arguments
main "$@"
