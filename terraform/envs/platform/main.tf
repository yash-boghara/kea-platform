# The one long-lived stack. Everything else is ephemeral and lives in Git,
# reconciled by ArgoCD.
#
# Deliberately small: this stack creates the cluster and the things a cluster
# cannot create for itself. Addons are NOT installed here — they are ArgoCD
# Applications in gitops/platform/, so the cluster's contents are reconciled
# rather than applied. See docs/adr/0004-terraform-vs-gitops-boundary.md

module "network" {
  source = "../../modules/network"

  name               = local.name
  cluster_name       = local.name
  cidr               = "10.20.0.0/16"
  availability_zones = ["ap-southeast-2a", "ap-southeast-2b"]

  # ~US$3/mo against ~US$66/mo for two managed NAT Gateways. The free S3 gateway
  # endpoint is always created and carries ECR image layers, which is the bulk of
  # the traffic. Single point of failure, accepted deliberately for ephemeral
  # workloads — docs/adr/0001-nat-strategy.md
  nat_mode = "instance"

  # Deliberately empty. Interface endpoints cost ~US$7.30/mo EACH, PER AZ — they
  # are a privacy control, not a cost saving. See the ADR.
  interface_endpoints = []

  tags = local.tags
}

module "eks" {
  source = "../../modules/eks"

  name       = local.name
  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.private_subnet_ids

  kubernetes_version = "1.31"

  # Karpenter handles the rest; this node group exists only to run Karpenter
  # itself and the other controllers that must not be evicted mid-scale-down.
  system_node_group = {
    instance_types = ["t4g.medium"]
    min_size       = 2
    max_size       = 3
    desired_size   = 2
    capacity_type  = "ON_DEMAND"
  }

  # Preview workloads are spot. They are ephemeral by definition, so
  # interruption is cheap — this is the right risk/cost trade here and worth
  # being able to explain.
  karpenter_capacity_types = ["spot", "on-demand"]

  enable_irsa                = true
  cluster_endpoint_public    = true
  cluster_endpoint_public_cidrs = var.admin_cidrs
  control_plane_log_types    = ["api", "audit", "authenticator"]

  tags = local.tags
}

module "ecr" {
  source = "../../modules/ecr"

  repositories = ["kea/app"]
  # Preview images accumulate fast — one per PR commit. Without a lifecycle
  # policy this is a slow, invisible cost leak.
  lifecycle_keep_last = 30
  scan_on_push        = true

  tags = local.tags
}

module "preview_data" {
  source = "../../modules/preview-data"

  name       = local.name
  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.private_subnet_ids

  # ONE instance, schema per PR. An instance per PR is the expensive mistake.
  instance_class    = "db.t4g.micro"
  allocated_storage = 20
  storage_encrypted = true
  multi_az          = false # previews do not need HA; say so out loud

  tags = merge(local.tags, { DataClassification = "internal" })
}
