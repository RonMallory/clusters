# Makefile for managing clusters repository
# Provides targets for tool checking, validation, deployment, and maintenance

# Variables
SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c
SCRIPTS_DIR := scripts
CHECK_TOOLS_SCRIPT := $(SCRIPTS_DIR)/check-tools.sh
INSTALL_TOOLS_SCRIPT := $(SCRIPTS_DIR)/install-tools.sh
SCAN_MANIFESTS_SCRIPT := $(SCRIPTS_DIR)/scan-manifests.sh
SCAN_SECRETS_SCRIPT := $(SCRIPTS_DIR)/scan-secrets.sh
KIND_MANAGER_SCRIPT := $(SCRIPTS_DIR)/kind-cluster-manager.sh

# Default target
.DEFAULT_GOAL := help

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
NC := \033[0m

##@ General

.PHONY: help
help: ## Display this help message
	@echo "Clusters Repository Management"
	@echo "============================="
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Prerequisites

.PHONY: check-tools
check-tools: ## Check for required development and deployment tools
	@echo "Checking for required tools..."
	@$(CHECK_TOOLS_SCRIPT)

##@ Development

.PHONY: validate
validate: check-tools ## Validate all Kubernetes manifests and configurations
	@echo "Validating Kubernetes manifests..."
	@find . -name "*.yaml" -o -name "*.yml" | grep -E "(kustomization|helmrelease)" | while read -r file; do \
		echo "Validating $$file"; \
		kubectl apply --dry-run=client --validate=true -f "$$file" > /dev/null 2>&1 || { \
			echo "$(RED)Error validating $$file$(NC)"; \
			exit 1; \
		}; \
	done
	@echo "$(GREEN)All manifests validated successfully$(NC)"

.PHONY: lint
lint: check-tools ## Lint YAML files for syntax and style
	@echo "Linting YAML files..."
	@if command -v yamllint >/dev/null 2>&1; then \
		find . -name "*.yaml" -o -name "*.yml" | xargs yamllint -c .yamllint 2>/dev/null || yamllint .; \
	else \
		echo "$(YELLOW)yamllint not found, skipping YAML linting$(NC)"; \
	fi

.PHONY: format
format: ## Format and organize configuration files
	@echo "Formatting configuration files..."
	@find . -name "*.yaml" -o -name "*.yml" | while read -r file; do \
		if command -v yq >/dev/null 2>&1; then \
			yq eval -i 'sortKeys(..)' "$$file"; \
		fi \
	done
	@echo "$(GREEN)Files formatted$(NC)"

##@ KIND Cluster Management

.PHONY: kind-create
kind-create: check-tools ## Create a KIND cluster
	@echo "Creating KIND cluster..."
	@$(KIND_MANAGER_SCRIPT) create

.PHONY: kind-create-multi
kind-create-multi: check-tools ## Create multiple KIND clusters (usage: make kind-create-multi CLUSTERS="dev test staging")
	@if [ -z "$(CLUSTERS)" ]; then \
		echo "$(RED)Error: CLUSTERS parameter required. Usage: make kind-create-multi CLUSTERS=\"dev test staging\"$(NC)"; \
		exit 1; \
	fi
	@echo "Creating multiple KIND clusters..."
	@$(KIND_MANAGER_SCRIPT) create-multi "$(CLUSTERS)"

.PHONY: kind-create-custom
kind-create-custom: check-tools ## Create custom KIND cluster (usage: make kind-create-custom NAME=my-cluster WORKERS=3 PORTS="8080:80,8443:443")
	@echo "Creating custom KIND cluster..."
	@if [ -n "$(WORKERS)" ] && [ -n "$(PORTS)" ]; then \
		$(KIND_MANAGER_SCRIPT) create $(NAME) --workers $(WORKERS) --port-map "$(PORTS)"; \
	elif [ -n "$(WORKERS)" ]; then \
		$(KIND_MANAGER_SCRIPT) create $(NAME) --workers $(WORKERS); \
	elif [ -n "$(PORTS)" ]; then \
		$(KIND_MANAGER_SCRIPT) create $(NAME) --port-map "$(PORTS)"; \
	else \
		$(KIND_MANAGER_SCRIPT) create $(NAME); \
	fi

.PHONY: kind-delete
kind-delete: ## Delete KIND cluster
	@echo "Deleting KIND cluster..."
	@$(KIND_MANAGER_SCRIPT) delete

.PHONY: kind-delete-multi
kind-delete-multi: ## Delete multiple KIND clusters (usage: make kind-delete-multi CLUSTERS="dev test staging")
	@if [ -z "$(CLUSTERS)" ]; then \
		echo "$(RED)Error: CLUSTERS parameter required. Usage: make kind-delete-multi CLUSTERS=\"dev test staging\"$(NC)"; \
		exit 1; \
	fi
	@echo "Deleting multiple KIND clusters..."
	@$(KIND_MANAGER_SCRIPT) delete-multi "$(CLUSTERS)"

.PHONY: kind-delete-all
kind-delete-all: ## Delete all KIND clusters with confirmation
	@echo "Deleting all KIND clusters..."
	@$(KIND_MANAGER_SCRIPT) delete-all

.PHONY: kind-list
kind-list: ## List all KIND clusters
	@$(KIND_MANAGER_SCRIPT) list

.PHONY: kind-status
kind-status: ## Show status of KIND clusters (usage: make kind-status [NAME=cluster-name])
	@if [ -n "$(NAME)" ]; then \
		$(KIND_MANAGER_SCRIPT) status $(NAME); \
	else \
		$(KIND_MANAGER_SCRIPT) status; \
	fi

.PHONY: kind-reset
kind-reset: ## Reset KIND cluster - delete and recreate (usage: make kind-reset [NAME=cluster-name])
	@echo "Resetting KIND cluster..."
	@if [ -n "$(NAME)" ]; then \
		$(KIND_MANAGER_SCRIPT) reset $(NAME); \
	else \
		$(KIND_MANAGER_SCRIPT) reset; \
	fi

.PHONY: kind-bootstrap
kind-bootstrap: kind-create ## Bootstrap KIND cluster with Flux
	@echo "Bootstrapping KIND cluster with Flux..."
	@kubectl config use-context kind-local-cluster
	@if [ -f bootstrap/local/flux-bootstrap.yaml ]; then \
		kubectl apply -f bootstrap/local/flux-bootstrap.yaml; \
	else \
		flux install --export > bootstrap/local/flux-bootstrap.yaml; \
		kubectl apply -f bootstrap/local/flux-bootstrap.yaml; \
	fi

##@ Deployment

.PHONY: apply-local
apply-local: check-tools ## Apply local cluster configurations
	@echo "Applying local cluster configurations..."
	@kubectl config use-context kind-local-cluster
	@kustomize build clusters/local/infrastructure | kubectl apply -f -
	@kustomize build clusters/local/apps | kubectl apply -f -

.PHONY: apply-kind
apply-kind: ## Apply configurations to KIND cluster (NotImplemented)
	@echo "$(YELLOW)This feature is not implemented yet$(NC)"

.PHONY: apply-aws
apply-aws: ## Apply AWS cluster configurations (NotImplemented)
	@echo "$(YELLOW)This feature is not implemented yet$(NC)"

.PHONY: apply-azure
apply-azure: ## Apply Azure cluster configurations (NotImplemented)
	@echo "$(YELLOW)This feature is not implemented yet$(NC)"

.PHONY: apply-gcp
apply-gcp: ## Apply GCP cluster configurations (NotImplemented)
	@echo "$(YELLOW)This feature is not implemented yet$(NC)"

##@ Infrastructure

.PHONY: terraform-init
terraform-init: ## Initialize Terraform in all infrastructure directories (NotImplemented)
	@echo "$(YELLOW)This feature is not implemented yet$(NC)"

.PHONY: terraform-plan
terraform-plan: ## Run Terraform plan in all infrastructure directories (NotImplemented)
	@echo "$(YELLOW)This feature is not implemented yet$(NC)"

.PHONY: terraform-apply
terraform-apply: ## Apply Terraform configurations (requires confirmation) (NotImplemented)
	@echo "$(YELLOW)This feature is not implemented yet$(NC)"

##@ Maintenance

.PHONY: update-flux
update-flux: ## Update Flux components to latest version (NotImplemented)
	@echo "$(YELLOW)This feature is not implemented yet$(NC)"

.PHONY: update-helm-repos
update-helm-repos: ## Update Helm repositories (NotImplemented)
	@echo "$(YELLOW)This feature is not implemented yet$(NC)"

.PHONY: clean
clean: ## Clean up temporary files and caches
	@echo "Cleaning up temporary files..."
	@find . -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
	@find . -name "*.tfstate.backup" -delete 2>/dev/null || true
	@find . -name ".DS_Store" -delete 2>/dev/null || true
	@echo "$(GREEN)Cleanup completed$(NC)"

.PHONY: clean-reports
clean-reports: ## Clean up old scanning reports (keeps last 5 of each type)
	@echo "Cleaning up old scanning reports..."
	@if [ -d "reports/manifest-scans" ]; then \
		cd reports/manifest-scans && \
		ls -1dt */ 2>/dev/null | tail -n +6 | xargs rm -rf 2>/dev/null || true; \
		REMAINING=$$(ls -1d */ 2>/dev/null | wc -l || echo 0); \
		echo "$(GREEN)Manifest reports cleaned ($$REMAINING remaining)$(NC)"; \
	fi
	@if [ -d "reports/secret-scans" ]; then \
		cd reports/secret-scans && \
		ls -1dt */ 2>/dev/null | tail -n +6 | xargs rm -rf 2>/dev/null || true; \
		REMAINING=$$(ls -1d */ 2>/dev/null | wc -l || echo 0); \
		echo "$(GREEN)Secret scan reports cleaned ($$REMAINING remaining)$(NC)"; \
	fi

.PHONY: list-reports
list-reports: ## List available scan reports
	@echo "Available Scan Reports:"
	@echo "======================"
	@if [ -d "reports/manifest-scans" ]; then \
		echo "$(BLUE)Manifest Scans:$(NC)"; \
		cd reports/manifest-scans && \
		for dir in $$(ls -1dt */ 2>/dev/null | head -5); do \
			echo "  📁 $$dir"; \
			if [ -f "$$dir/scan-summary.txt" ]; then \
				head -1 "$$dir/scan-summary.txt" | sed 's/^/     /'; \
			fi; \
		done; \
		echo ""; \
	fi
	@if [ -d "reports/secret-scans" ]; then \
		echo "$(BLUE)Secret Scans:$(NC)"; \
		cd reports/secret-scans && \
		for dir in $$(ls -1dt */ 2>/dev/null | head -5); do \
			echo "  🔒 $$dir"; \
			if [ -f "$$dir/scan-summary.txt" ]; then \
				head -1 "$$dir/scan-summary.txt" | sed 's/^/     /'; \
			fi; \
		done; \
	fi

.PHONY: list-secret-reports
list-secret-reports: ## List available secret scan reports
	@echo "Available Secret Scan Reports:"
	@echo "============================="
	@if [ -d "reports/secret-scans" ]; then \
		cd reports/secret-scans && \
		for dir in $$(ls -1dt */ 2>/dev/null | head -10); do \
			echo "🔒 $$dir"; \
			if [ -f "$$dir/scan-summary.txt" ]; then \
				head -1 "$$dir/scan-summary.txt" | sed 's/^/   /'; \
			fi; \
		done; \
	else \
		echo "No secret scan reports found"; \
	fi

.PHONY: status
status: check-tools ## Show status of all clusters and components
	@echo "Cluster Status Overview"
	@echo "======================="
	@echo "Available contexts:"
	@kubectl config get-contexts -o name | grep -E "(kind-local-cluster|aws-cluster|azure-cluster|gcp-cluster)" || echo "No cluster contexts found"
	@echo ""
	@echo "Flux status (if available):"
	@flux get all 2>/dev/null || echo "Flux not available or not installed"

##@ Security

.PHONY: scan-manifests
scan-manifests: check-tools ## Scan Kubernetes manifests for security issues and best practices
	@$(SCRIPTS_DIR)/scan-manifests.sh --verbose

.PHONY: scan-manifests-quick
scan-manifests-quick: check-tools ## Quick scan with essential tools only (kubescape, trivy)
	@$(SCRIPTS_DIR)/scan-manifests.sh --tools kubescape,trivy --verbose

.PHONY: scan-manifests-syntax
scan-manifests-syntax: ## YAML syntax validation only
	@$(SCRIPTS_DIR)/scan-manifests.sh --tools yamllint --verbose

.PHONY: check-secrets
check-secrets: ## Check for potential secrets in configuration files
	@$(SCAN_SECRETS_SCRIPT) --verbose

.PHONY: scan-secrets
scan-secrets: check-tools ## Comprehensive secret scanning with TruffleHog
	@$(SCAN_SECRETS_SCRIPT) --modes git,filesystem --verbose

.PHONY: scan-secrets-git
scan-secrets-git: ## Scan git history for committed secrets
	@$(SCAN_SECRETS_SCRIPT) --modes git --verbose

.PHONY: scan-secrets-files
scan-secrets-files: ## Scan filesystem for secrets in files
	@$(SCAN_SECRETS_SCRIPT) --modes filesystem --verbose

.PHONY: update-sealed-secrets
update-sealed-secrets: check-tools ## Update sealed secrets controller
	@echo "Updating sealed secrets controller..."
	@if [ -f platform/components/sealed-secrets/helmrelease.yaml ]; then \
		kubectl apply -f platform/components/sealed-secrets/; \
	else \
		echo "$(YELLOW)Sealed secrets configuration not found$(NC)"; \
	fi

##@ Development Environment

.PHONY: install-tools
install-tools: ## Install missing tools automatically
	@echo "Installing missing tools..."
	@$(INSTALL_TOOLS_SCRIPT) --all

.PHONY: install-tools-scan
install-tools-scan: ## Install only Kubernetes manifest scanning tools
	@echo "Installing Kubernetes scanning tools..."
	@$(INSTALL_TOOLS_SCRIPT) --scan-only

.PHONY: install-tool
install-tool: ## Install specific tool (usage: make install-tool TOOL=kubectl)
	@if [ -z "$(TOOL)" ]; then \
		echo "$(RED)Error: TOOL parameter required. Usage: make install-tool TOOL=kubectl$(NC)"; \
		exit 1; \
	fi
	@echo "Installing $(TOOL)..."
	@$(INSTALL_TOOLS_SCRIPT) $(TOOL)

.PHONY: list-tools
list-tools: ## List all available tools for installation
	@$(INSTALL_TOOLS_SCRIPT) --list

# Prevent make from deleting intermediate files
.PRECIOUS: %

# Ensure scripts directory exists
$(SCRIPTS_DIR):
	@mkdir -p $(SCRIPTS_DIR)
