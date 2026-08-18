variable "name" {
  description = "Cluster name. Also used as the Karpenter discovery tag value, so it must match what the network module was given."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the control plane ENIs and worker nodes."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "EKS requires subnets in at least two availability zones."
  }
}

variable "kubernetes_version" {
  description = <<-EOT
    EKS minor version. Check what is currently supported before setting this —
    versions age out of standard support roughly 14 months after release, and
    extended support is billed at a premium:
      aws eks describe-cluster-versions --query 'clusterVersions[].clusterVersion'
  EOT
  type        = string
  default     = "1.33"
}

variable "system_node_group" {
  description = <<-EOT
    The bootstrap managed node group. This exists only to run Karpenter itself
    plus the controllers that must not be evicted mid-scale-down (CoreDNS, the
    Karpenter controller). Everything else lands on Karpenter-provisioned nodes.

    Chicken-and-egg: Karpenter cannot provision the nodes Karpenter runs on.
  EOT
  type = object({
    instance_types = list(string)
    min_size       = number
    max_size       = number
    desired_size   = number
    capacity_type  = string
  })
  default = {
    instance_types = ["t4g.medium"]
    min_size       = 2
    max_size       = 3
    desired_size   = 2
    capacity_type  = "ON_DEMAND"
  }

  validation {
    condition     = var.system_node_group.min_size >= 2
    error_message = "At least two system nodes, so a node replacement cannot take CoreDNS down with it."
  }
}

variable "enable_irsa" {
  description = "Create the OIDC provider for IAM Roles for Service Accounts. Required by Karpenter, external-dns, cert-manager and the EBS CSI driver as configured here."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public" {
  description = "Expose the Kubernetes API publicly. Needed for GitHub Actions to reach the cluster without a self-hosted runner or VPN."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_cidrs" {
  description = <<-EOT
    CIDRs allowed to reach the public API endpoint. Leaving this open to the
    world is how portfolio clusters get cryptomined — an exposed API endpoint is
    scanned within minutes.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.cluster_endpoint_public_cidrs, "0.0.0.0/0")
    error_message = "Refusing 0.0.0.0/0 on the public API endpoint. Set your own IP, or set cluster_endpoint_public = false."
  }
}

variable "control_plane_log_types" {
  description = "Control plane logs to ship to CloudWatch. 'audit' is the one that matters for incident response, and also the noisiest — watch the cost."
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

variable "log_retention_days" {
  description = "CloudWatch retention for control plane logs. The default log group is create-on-demand with infinite retention, which quietly accrues cost forever."
  type        = number
  default     = 14
}

variable "admin_principal_arns" {
  description = "Additional IAM principals granted cluster-admin via EKS access entries. The creating principal is bootstrapped automatically."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to all resources. Must satisfy policies/terraform/tagging.rego."
  type        = map(string)
  default     = {}
}
