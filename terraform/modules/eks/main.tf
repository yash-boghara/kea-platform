# EKS control plane, IRSA, and the bootstrap node group.
#
# Karpenter's IAM, interruption queue and node role live in karpenter.tf.
# Cluster *contents* (addons deployed as workloads, policies, the platform
# stack) are deliberately NOT here — they are ArgoCD Applications in
# gitops/platform/. See docs/adr/0004-terraform-vs-gitops-boundary.md
#
# The split: Terraform owns things a cluster cannot create for itself. Git owns
# everything running inside it.

data "aws_partition" "current" {}

locals {
  # EKS-managed addons need the cluster to exist and IRSA to be wired before
  # they can assume roles, hence the explicit ordering further down.
  oidc_provider_url = var.enable_irsa ? replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "") : ""
}

# --- Secrets encryption -------------------------------------------------
#
# Envelope encryption for Kubernetes Secrets at rest in etcd. Without this,
# Secrets are only protected by EKS's own disk encryption, and anyone with etcd
# read access sees plaintext. NZISM 17.1 / 22.1.

resource "aws_kms_key" "secrets" {
  description             = "${var.name} EKS secrets envelope encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  tags = merge(var.tags, { Name = "${var.name}-secrets" })
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.name}-eks-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

# --- Control plane IAM --------------------------------------------------

data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.name}-cluster"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster" {
  for_each = toset([
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy",
  ])
  role       = aws_iam_role.cluster.name
  policy_arn = each.value
}

# --- Control plane logging ---------------------------------------------
#
# Created explicitly rather than letting EKS create it on demand, because the
# implicit log group never expires. Retention on an audit log is a real cost
# line once the cluster is busy.

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.name}/cluster"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# --- Cluster ------------------------------------------------------------

resource "aws_eks_cluster" "this" {
  name     = var.name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  enabled_cluster_log_types = var.control_plane_log_types

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = var.cluster_endpoint_public
    public_access_cidrs     = var.cluster_endpoint_public ? var.cluster_endpoint_public_cidrs : null
  }

  encryption_config {
    provider {
      key_arn = aws_kms_key.secrets.arn
    }
    resources = ["secrets"]
  }

  # API mode instead of the legacy aws-auth ConfigMap. The ConfigMap approach
  # is editable by anyone with write access to kube-system and has no audit
  # trail; access entries are IAM resources, so they are logged in CloudTrail
  # and manageable by Terraform.
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_cloudwatch_log_group.cluster,
  ]

  tags = merge(var.tags, { Name = var.name })
}

# --- IRSA ---------------------------------------------------------------
#
# The OIDC provider lets a Kubernetes ServiceAccount assume an IAM role, so
# pods get scoped AWS credentials without any static keys on the node. This is
# the mechanism Karpenter, external-dns and cert-manager all rely on.

data "tls_certificate" "oidc" {
  count = var.enable_irsa ? 1 : 0
  url   = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  count = var.enable_irsa ? 1 : 0

  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc[0].certificates[0].sha1_fingerprint]

  tags = merge(var.tags, { Name = "${var.name}-oidc" })
}

# --- Access entries -----------------------------------------------------

resource "aws_eks_access_entry" "admins" {
  for_each = toset(var.admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  type          = "STANDARD"
  tags          = var.tags
}

resource "aws_eks_access_policy_association" "admins" {
  for_each = toset(var.admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admins]
}

# --- Bootstrap node group ----------------------------------------------

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.name}-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    # SSM lets you get a shell on a node without opening SSH or running a
    # bastion. Worth it the first time a node fails to join the cluster.
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ])
  role       = aws_iam_role.node.name
  policy_arn = each.value
}

resource "aws_eks_node_group" "system" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.name}-system"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  instance_types = var.system_node_group.instance_types
  capacity_type  = var.system_node_group.capacity_type

  scaling_config {
    min_size     = var.system_node_group.min_size
    max_size     = var.system_node_group.max_size
    desired_size = var.system_node_group.desired_size
  }

  update_config {
    max_unavailable = 1
  }

  # Karpenter and CoreDNS are pinned here by a toleration in their Helm values;
  # the taint stops general workloads landing on the system nodes and competing
  # with the controller that manages every other node.
  taint {
    key    = "kea.platform/system"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  labels = {
    "kea.platform/nodegroup" = "system"
  }

  depends_on = [aws_iam_role_policy_attachment.node]

  lifecycle {
    # Terraform and the cluster autoscaler would otherwise fight over this.
    ignore_changes = [scaling_config[0].desired_size]
  }

  tags = merge(var.tags, { Name = "${var.name}-system" })
}

# --- EKS managed addons -------------------------------------------------
#
# These are control-plane-managed, not workloads we reconcile from Git, so they
# belong in Terraform. Anything installed with Helm belongs in gitops/platform/.

resource "aws_eks_addon" "vpc_cni" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "vpc-cni"
  addon_version = null # let EKS pick the default for the cluster version

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [aws_eks_node_group.system]
  tags       = var.tags
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [aws_eks_node_group.system]
  tags       = var.tags
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  # CoreDNS must tolerate the system taint or it stays Pending forever on a
  # cluster whose only nodes are tainted — a genuinely confusing first failure.
  configuration_values = jsonencode({
    tolerations = [{
      key      = "kea.platform/system"
      operator = "Equal"
      value    = "true"
      effect   = "NoSchedule"
    }]
  })

  depends_on = [aws_eks_node_group.system]
  tags       = var.tags
}
