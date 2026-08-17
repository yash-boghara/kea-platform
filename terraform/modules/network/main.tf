# VPC for the Kea platform cluster.
#
# Layout per AZ: one public subnet (load balancers, NAT) and one private subnet
# (EKS nodes, RDS). Nodes never get public IPs.
#
# The interesting decision in this module is egress — see var.nat_mode and
# docs/adr/0001-nat-strategy.md. Everything else is conventional.

locals {
  az_count = length(var.availability_zones)

  # Carve /20s out of the /16: public subnets first, then private.
  # /20 = 4094 usable addresses per subnet, which matters because the AWS VPC CNI
  # assigns real VPC IPs to every pod, not just every node.
  public_cidrs  = [for i in range(local.az_count) : cidrsubnet(var.cidr, 4, i)]
  private_cidrs = [for i in range(local.az_count) : cidrsubnet(var.cidr, 4, i + local.az_count)]

  # Which resource actually routes 0.0.0.0/0 for the private subnets.
  use_nat_gateway  = var.nat_mode == "gateway"
  use_nat_instance = var.nat_mode == "instance"
}

resource "aws_vpc" "this" {
  cidr_block = var.cidr

  # Both required by EKS: the kubelet and CoreDNS resolve via the VPC resolver.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = var.name })
}

# --- Subnets ------------------------------------------------------------
#
# The kubernetes.io/role tags are not decoration. The AWS Load Balancer
# Controller discovers where to place ELBs by reading them, and Karpenter finds
# subnets to launch nodes into via the karpenter.sh/discovery tag. Get these
# wrong and the failure is a controller silently doing nothing, which is a
# genuinely annoying thing to debug.

resource "aws_subnet" "public" {
  count = local.az_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name                                        = "${var.name}-public-${var.availability_zones[count.index]}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    Tier                                        = "public"
  })
}

resource "aws_subnet" "private" {
  count = local.az_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.private_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name                                        = "${var.name}-private-${var.availability_zones[count.index]}"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "karpenter.sh/discovery"                    = var.cluster_name
    Tier                                        = "private"
  })
}

# --- Public routing -----------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-public" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = local.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# --- Private routing ----------------------------------------------------
#
# One route table per AZ. With a NAT Gateway this is what keeps traffic in-AZ
# (cross-AZ NAT traffic is billed as inter-AZ data transfer on top of NAT
# processing — a classic invisible cost). With a NAT instance there is only one
# instance, so the tables all point at it and cross-AZ charges do apply; that is
# part of the trade-off for the ~US$30/mo saving.

resource "aws_route_table" "private" {
  count  = local.az_count
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-private-${var.availability_zones[count.index]}" })
}

resource "aws_route_table_association" "private" {
  count          = local.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Managed NAT Gateway: one per AZ so a single AZ failure cannot take out egress
# for the whole cluster.
resource "aws_eip" "nat" {
  count      = local.use_nat_gateway ? local.az_count : 0
  domain     = "vpc"
  depends_on = [aws_internet_gateway.this]
  tags       = merge(var.tags, { Name = "${var.name}-nat-${var.availability_zones[count.index]}" })
}

resource "aws_nat_gateway" "this" {
  count = local.use_nat_gateway ? local.az_count : 0

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  depends_on    = [aws_internet_gateway.this]

  tags = merge(var.tags, { Name = "${var.name}-${var.availability_zones[count.index]}" })
}

resource "aws_route" "private_nat_gateway" {
  count = local.use_nat_gateway ? local.az_count : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[count.index].id
}

resource "aws_route" "private_nat_instance" {
  count = local.use_nat_instance ? local.az_count : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat[0].primary_network_interface_id
}

# --- NAT instance -------------------------------------------------------
#
# A t4g.nano running iptables masquerade. ~US$3/mo against ~US$33/mo for a
# managed NAT Gateway.
#
# Honest trade-off: this is a single point of failure and you patch it yourself.
# If it dies, image pulls and any outbound API call from private subnets fail.
# Acceptable for ephemeral preview environments; not what you would run for
# production, and saying so is the point of the ADR.

data "aws_ssm_parameter" "al2023_arm64" {
  count = local.use_nat_instance ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "aws_security_group" "nat" {
  count = local.use_nat_instance ? 1 : 0

  name        = "${var.name}-nat"
  description = "NAT instance: accept all traffic originating inside the VPC, forward it out"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "All traffic from within the VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.cidr]
  }

  egress {
    description = "Forwarded traffic to the internet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-nat" })
}

resource "aws_instance" "nat" {
  count = local.use_nat_instance ? 1 : 0

  ami           = data.aws_ssm_parameter.al2023_arm64[0].value
  instance_type = var.nat_instance_type
  subnet_id     = aws_subnet.public[0].id

  vpc_security_group_ids = [aws_security_group.nat[0].id]

  # Without this the VPC drops packets whose source/destination is not this
  # instance — which is every packet it is meant to forward. The single most
  # commonly forgotten line when hand-rolling a NAT instance.
  source_dest_check = false

  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    # Persist across reboots.
    echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-nat.conf
    sysctl -p /etc/sysctl.d/99-nat.conf

    dnf install -y iptables-services
    IFACE=$(ip route show default | awk '{print $5; exit}')
    iptables -t nat -A POSTROUTING -o "$IFACE" -s ${var.cidr} -j MASQUERADE
    iptables -F FORWARD
    service iptables save
    systemctl enable --now iptables
  EOF

  metadata_options {
    http_tokens   = "required" # IMDSv2 only; IMDSv1 is an SSRF credential-theft vector
    http_endpoint = "enabled"
  }

  root_block_device {
    encrypted   = true # policies/terraform/encryption.rego enforces this
    volume_size = 8
    volume_type = "gp3"
  }

  tags = merge(var.tags, { Name = "${var.name}-nat" })
}

# --- VPC endpoints ------------------------------------------------------

# Gateway endpoint. Free, and it keeps ECR image-layer traffic (which lives in
# S3) off the NAT path entirely. Create this in every mode — there is no reason
# not to.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = merge(var.tags, { Name = "${var.name}-s3" })
}

# Interface endpoints. ~US$7.30/mo each PER AZ. Empty by default — see the note
# on var.interface_endpoints. These are a privacy/compliance tool, not a cost
# saving.
resource "aws_security_group" "endpoints" {
  count = length(var.interface_endpoints) > 0 ? 1 : 0

  name        = "${var.name}-vpce"
  description = "HTTPS from within the VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.cidr]
  }

  tags = merge(var.tags, { Name = "${var.name}-vpce" })
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(var.interface_endpoints)

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints[0].id]
  private_dns_enabled = true

  tags = merge(var.tags, { Name = "${var.name}-${each.value}" })
}

data "aws_region" "current" {}
