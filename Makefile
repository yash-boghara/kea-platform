.DEFAULT_GOAL := help
SHELL := /bin/bash

TF_DIR      := terraform/envs/platform
CLUSTER     := kea-platform
REGION      := ap-southeast-2

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-22s\033[0m %s\n", $$1, $$2}'

# --- setup -------------------------------------------------------------

.PHONY: bootstrap
bootstrap: ## Install toolchain (Phase 0)
	brew bundle --file=Brewfile

.PHONY: kubeconfig
kubeconfig: ## Point kubectl at the platform cluster
	aws eks update-kubeconfig --name $(CLUSTER) --region $(REGION)

# --- terraform ---------------------------------------------------------

.PHONY: init plan apply destroy
init: ## terraform init
	cd $(TF_DIR) && terraform init

plan: ## terraform plan + policy gate (same checks CI runs)
	cd $(TF_DIR) && terraform plan -out=tfplan && terraform show -json tfplan > tfplan.json
	conftest test $(TF_DIR)/tfplan.json --policy policies/terraform --all-namespaces --output table

apply: ## terraform apply
	cd $(TF_DIR) && terraform apply tfplan

destroy: ## Tear the platform down to zero cost
	@echo "This destroys the cluster, database and network. Preview envs go with it."
	@read -p "Type the cluster name to confirm: " c && [ "$$c" = "$(CLUSTER)" ]
	cd $(TF_DIR) && terraform destroy

# --- policy ------------------------------------------------------------

.PHONY: policy-test policy-check
policy-test: ## Run Rego unit tests
	conftest verify -p policies/

policy-check: ## Run Kyverno policies against the chart, offline
	helm template app/chart | kyverno apply policies/kyverno/ --resource -

# --- gitops ------------------------------------------------------------

.PHONY: argocd-bootstrap argocd-ui
argocd-bootstrap: ## The one manual kubectl apply, ever (Phase 3)
	kubectl apply -f gitops/bootstrap/root-app.yaml

argocd-ui: ## Port-forward the ArgoCD UI
	@echo "https://localhost:8080  user: admin"
	@kubectl -n argocd get secret argocd-initial-admin-secret \
		-o jsonpath='{.data.password}' | base64 -d; echo
	kubectl port-forward -n argocd svc/argocd-server 8080:443

# --- operations --------------------------------------------------------

.PHONY: envs reap-dry-run cost
envs: ## List active preview environments with age and owner
	@kubectl get ns -l kea.platform/kind=preview \
		-o custom-columns='NAMESPACE:.metadata.name,PR:.metadata.labels.kea\.platform/pr,AGE:.metadata.creationTimestamp'

reap-dry-run: ## Show what the reaper would delete, without deleting
	kubectl create job --from=cronjob/kea-reaper reaper-dryrun-$$(date +%s) -n platform-jobs -- \
		/reaper --dry-run

cost: ## Per-namespace cost for the last 7 days
	./platform/cost/report.sh 7
