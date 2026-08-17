# Architecture Decision Records

Write one for every decision where you rejected a reasonable alternative. The
value is not the decision — it is showing that you knew there was a choice, and
can argue the other side.

Format: context → options considered → decision → consequences (including the
bad ones). Keep them under a page.

## To write as you build

| ADR | Decision | Phase |
|---|---|---|
| 0001 | NAT Gateway vs VPC endpoints vs NAT instance | 1 |
| 0002 | ap-southeast-2 (Sydney) vs ap-southeast-6 (NZ) — cost and service availability vs in-country residency | 1 |
| 0003 | Preview data: schema-per-PR on shared RDS vs instance-per-PR vs containerised Postgres | 5 |
| 0004 | Terraform/GitOps boundary — what Terraform owns vs what ArgoCD owns | 3 |
| 0005 | Compliance scope — which NZISM controls are in scope and why the rest are not | 2 |
| 0006 | Namespace-per-PR vs cluster-per-PR (cost vs isolation) | 4 |
| 0007 | Kyverno vs OPA Gatekeeper for admission | 6 |

ADR 0002 and 0006 are the two most likely to be probed in an NZ interview — one
is the data sovereignty question, the other is the cost/isolation trade-off every
platform team argues about.
