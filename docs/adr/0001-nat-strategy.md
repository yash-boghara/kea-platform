# ADR 0001 — Private subnet egress strategy

**Status:** Accepted
**Date:** 2026-08-18
**Phase:** 1

## Context

EKS nodes run in private subnets and must reach the internet to pull container
images from ECR, call AWS APIs (STS for IRSA, EC2 for Karpenter, CloudWatch for
logs), and fetch Let's Encrypt certificates.

This is the largest fixed cost in the platform after the EKS control plane, and
the choice is not obvious — the intuitive answer is wrong.

## Options considered

Costs are ap-southeast-2, on-demand, excluding data transfer.

### A. Managed NAT Gateway, one per AZ

US$0.045/hr each = **~US$65.70/mo** for two AZs, plus US$0.045/GB processed.

Zero operational burden, AWS-managed HA within each AZ, scales to 100 Gbps. This
is the correct production answer and what I would deploy at work.

### B. Managed NAT Gateway, single AZ

**~US$32.85/mo.** Halves the cost but introduces a cross-AZ dependency: nodes in
AZ-b route through AZ-a, so egress dies if AZ-a does, and inter-AZ data transfer
is billed at US$0.01/GB each way on top of NAT processing.

### C. No NAT — interface VPC endpoints only

Interface endpoints cost US$0.01/hr **per endpoint, per AZ**. The five services
the nodes need (`ecr.api`, `ecr.dkr`, `logs`, `sts`, `ec2`) across two AZs:

```
5 endpoints × 2 AZs × US$0.0073/hr × 730 hr = ~US$73/mo
```

**This is more expensive than option A**, which is the counterintuitive part.
Endpoints are commonly described as "avoiding NAT costs"; at small scale they
invert it. They also cannot cover non-AWS egress at all — Let's Encrypt, Helm
chart repositories and OS package mirrors would still be unreachable.

The saving only materialises at high data volume, where the US$0.045/GB NAT
processing charge dominates the fixed endpoint cost. A preview-environment
cluster moves nowhere near that much data.

### D. NAT instance — t4g.nano running iptables masquerade

**~US$3.07/mo** (US$0.0042/hr) plus US$0.80/mo for an 8 GB gp3 root volume.
Roughly **US$4/mo all-in**, about 6% of option A.

t4g.nano sustains ~32 Gbps of burst network throughput, far beyond what image
pulls for a handful of preview environments require.

## Decision

**Option D — NAT instance — as the default, with `nat_mode` exposed as a variable
so all three strategies can be demonstrated.**

The free S3 *gateway* endpoint is created in every mode regardless. Gateway
endpoints are priced differently from interface endpoints (they are free), and
ECR stores image layers in S3, so this keeps the largest traffic component off
the NAT path at no cost.

## Consequences

**Good**
- ~US$62/mo saved against the production-shaped option, on a portfolio budget
- The `nat_mode` variable makes the trade-off demonstrable rather than asserted
- The `estimated_monthly_egress_cost_usd` output surfaces the difference in
  `terraform output`

**Bad — accepted deliberately**
- **Single point of failure.** One instance, one AZ. If it dies, every private
  subnet loses egress: image pulls fail, IRSA token exchange fails, and pods
  stuck in `ImagePullBackOff` is the symptom. Preview environments are ephemeral
  and this is a portfolio cluster, so the blast radius is acceptable.
- **I patch it.** An unattended AL2023 box needs OS updates. Mitigation: it is
  disposable — `terraform taint` and re-apply rebuilds it in ~2 minutes.
- **Cross-AZ data transfer.** Nodes in AZ-b route through the instance in AZ-a at
  US$0.01/GB each way. Immaterial at this volume, real at scale.
- **No throughput autoscaling.** A managed NAT Gateway absorbs a traffic spike;
  this does not.

## Revisit when

- Sustained egress exceeds ~700 GB/mo, where NAT Gateway processing charges start
  to rival the instance's simplicity premium
- The cluster hosts anything with a real availability target
- A compliance requirement demands no internet egress at all, at which point
  option C becomes correct *for its stated reason* — privacy, not cost

## Note on the initial error

The first draft of this project asserted that VPC endpoints would avoid the NAT
Gateway cost. That was wrong: it conflated gateway endpoints (free) with
interface endpoints (~US$7.30/mo each per AZ), and would have made the platform
more expensive while claiming a saving. Recorded here because the failure mode —
a plausible cost heuristic applied without checking the pricing page — is worth
remembering.
