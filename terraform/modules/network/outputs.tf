output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR, for security group rules in dependent modules."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs — internet-facing load balancers and the NAT instance."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs — EKS nodes and RDS. No public IPs here."
  value       = aws_subnet.private[*].id
}

output "availability_zones" {
  description = "AZs in use, in the same order as the subnet outputs."
  value       = var.availability_zones
}

output "nat_mode" {
  description = "Which egress strategy is active. Surfaced so the cost report can attribute the difference."
  value       = var.nat_mode
}

output "nat_public_ip" {
  description = "Public IP egress traffic appears to come from. Null unless nat_mode = instance. Useful when a third-party API needs an allowlist entry."
  value       = local.use_nat_instance ? aws_instance.nat[0].public_ip : null
}

output "estimated_monthly_egress_cost_usd" {
  description = <<-EOT
    Rough fixed monthly cost of the chosen egress strategy, excluding data transfer.
    Not authoritative — Infracost in CI is. This exists so the trade-off is visible
    in `terraform output` rather than buried in a doc nobody opens.
  EOT
  value = (
    var.nat_mode == "gateway" ? 32.85 * local.az_count :
    var.nat_mode == "instance" ? 3.07 :
    length(var.interface_endpoints) * 7.30 * local.az_count
  )
}
