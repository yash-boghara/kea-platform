variable "region" {
  description = "AWS region. Constrained by policies/terraform/residency.rego to NZ/AU."
  type        = string
  default     = "ap-southeast-2"
}

variable "admin_cidrs" {
  description = <<-EOT
    CIDRs permitted to reach the EKS public API endpoint.
    Set this to your own IP. Leaving it as 0.0.0.0/0 is the single most common
    way a portfolio cluster gets cryptomined.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.admin_cidrs, "0.0.0.0/0")
    error_message = "admin_cidrs must not include 0.0.0.0/0. Use your own IP."
  }
}

variable "base_domain" {
  description = "Route53 hosted zone for preview hostnames, e.g. kea.example.nz"
  type        = string
}
