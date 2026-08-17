variable "name" {
  description = "Name prefix for all resources in this module."
  type        = string
}

variable "cidr" {
  description = "VPC CIDR. /16 gives room for EKS pod IPs via the VPC CNI, which allocates real VPC addresses per pod — undersize this and you hit IP exhaustion under load, not at apply time."
  type        = string
  default     = "10.20.0.0/16"
}

variable "availability_zones" {
  description = "AZs to spread subnets across. Two is enough for a portfolio cluster; three is the production default."
  type        = list(string)
}

variable "nat_mode" {
  description = <<-EOT
    How private subnets reach the internet. This is the single biggest cost lever
    in the whole platform — see docs/adr/0001-nat-strategy.md.

      "instance" — one t4g.nano doing NAT (~US$3/mo). Cheapest workable option.
                   Single point of failure; if it dies, image pulls fail.
      "gateway"  — AWS managed NAT Gateway (~US$33/mo + US$0.045/GB processed).
                   Zero ops. What you would actually run in production.
      "none"     — no egress. Requires interface endpoints for every AWS API the
                   nodes touch, at ~US$7.30/mo per endpoint per AZ. Counterintuitively
                   the MOST expensive option at this scale (~US$73/mo for five
                   endpoints across two AZs).

    The S3 gateway endpoint is created in all modes because it is free and carries
    the bulk of ECR image-layer traffic.
  EOT
  type        = string
  default     = "instance"

  validation {
    condition     = contains(["instance", "gateway", "none"], var.nat_mode)
    error_message = "nat_mode must be one of: instance, gateway, none."
  }
}

variable "nat_instance_type" {
  description = "Instance type when nat_mode = instance. t4g.nano is ~US$3/mo and saturates around 32 Gbps burst — far more than a preview cluster needs."
  type        = string
  default     = "t4g.nano"
}

variable "interface_endpoints" {
  description = <<-EOT
    Interface VPC endpoints to create. Each costs ~US$7.30/mo PER AZ, plus data.
    Empty by default — do not enable these for cost reasons, because they are not
    a saving. Enable them when you need private-only egress for a compliance
    reason, and say that is why.
  EOT
  type        = list(string)
  default     = []
}

variable "cluster_name" {
  description = "EKS cluster name, used for subnet discovery tags. Karpenter and the AWS load balancer controller find subnets by these tags, so they must match the cluster exactly."
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources. Must satisfy policies/terraform/tagging.rego."
  type        = map(string)
  default     = {}
}
