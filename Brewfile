# Phase 0 toolchain. `make bootstrap`
#
# Note: `brew bundle` is atomic — one unresolvable formula aborts the whole
# batch, so keep the taps below in sync with the formulae that need them.

# Terraform left homebrew-core when HashiCorp relicensed it to BUSL 1.1;
# it now ships from HashiCorp's own tap. Same for tflint.
# (If you ever need a fully OSS toolchain, OpenTofu is the fork — but NZ job
# postings say "Terraform", so Terraform is what this project uses.)
tap "hashicorp/tap"
tap "terraform-linters/tap"

# Core
brew "hashicorp/tap/terraform"
brew "awscli"
brew "kubernetes-cli"
brew "helm"

# GitOps
brew "argocd"

# Policy
brew "conftest"
brew "kyverno"
brew "opa"

# Supply chain
brew "trivy"
brew "syft"
brew "cosign"

# FinOps
brew "infracost"

# Quality of life
brew "k9s"           # cluster TUI; you will live in this
brew "stern"         # multi-pod log tailing
brew "kubectx"       # context/namespace switching
brew "jq"
brew "yq"
brew "pre-commit"
brew "terraform-linters/tap/tflint"
brew "terraform-docs"
