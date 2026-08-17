# Kea — Ephemeral Environment Platform

Open a pull request, get a live, isolated, TLS-terminated environment with a seeded
database in under two minutes. Merge or close it, and the environment reaps itself.
Every change is gated by policy-as-code before it ever reaches the cluster.

Built as an end-to-end platform engineering portfolio project: EKS, Terraform,
GitOps, admission control, supply-chain security, per-environment cost attribution,
and NZISM-aligned compliance controls.

---

## The demo (3 minutes)

1. Open a PR against `app/`. ArgoCD's PR generator provisions a namespace, a seeded
   Postgres schema, a DNS record and a certificate. The bot comments the URL.
2. Open the URL. The change is live.
3. Push a commit that requests a privileged container. Kyverno rejects it at
   admission; the PR check goes red with a readable reason.
4. Push a Terraform change that creates an unencrypted S3 bucket. Conftest blocks
   the plan in CI, citing the NZISM control it violates.
5. Close the PR. The environment is gone within 60 seconds; the reaper sweeps
   anything orphaned.

## Architecture

```
  GitHub PR
      │
      ├─ CI: build → SBOM (syft) → scan (trivy) → sign (cosign) → ECR
      │
      ├─ CI: terraform plan → conftest (NZISM + tagging policy) → apply
      │
      └─ ArgoCD ApplicationSet (PR generator)
              │
              ▼
        EKS cluster (ap-southeast-2)
              │
    ┌─────────┼──────────────┬──────────────┬─────────────┐
    ▼         ▼              ▼              ▼             ▼
 namespace  Kyverno     external-dns   cert-manager   Prometheus
 pr-1234    admission    Route53        Let's Encrypt   + SLOs
    │
    ├─ app deployment (signed image, verified at admission)
    ├─ seeded Postgres schema (anonymised snapshot)
    └─ TTL annotation → reaper CronJob
```

See [docs/architecture.md](docs/architecture.md) for the detailed diagram and
[docs/adr/](docs/adr/) for the decisions and their trade-offs.

## Metrics

> Fill this in as you build. This table is the single highest-value thing in the
> repo — it is what a recruiter reads. Replace every `—` with a measured number.

| Metric | Baseline | Now | How measured |
|---|---|---|---|
| PR → usable URL (p50) | — | — | Actions job duration, `preview-env.yml` |
| PR → usable URL (p95) | — | — | same |
| Environment teardown time | — | — | reaper logs |
| Orphaned environments per week | — | — | reaper metrics |
| Cost per preview environment / day | — | — | cost allocation tags → CUR |
| Platform cost / month | — | — | AWS Cost Explorer |
| Policy violations caught pre-merge | — | — | conftest + Kyverno audit counts |
| Image CVEs (critical) shipped | — | — | trivy in CI |
| Deploy frequency | — | — | ArgoCD sync events |
| Change failure rate | — | — | rollbacks / total syncs |

## Cost

Target: **under NZ$40/month**, with the cluster running only when in use.

| Component | Approx / month |
|---|---|
| EKS control plane | ~US$73 → see note |
| Karpenter-managed spot nodes | — |
| Route53 hosted zone | ~US$0.50 |
| ECR storage | — |
| NAT Gateway | — (use a NAT instance or VPC endpoints instead) |

**Note:** the EKS control plane is the dominant cost and is charged per hour whether
or not you use it. Run `make platform-down` when not developing; a single shared
cluster with namespace-per-PR isolation costs a fraction of cluster-per-PR. Avoid
the managed NAT Gateway — it is the classic silent portfolio-project bill.

## Repo layout

| Path | What lives here |
|---|---|
| `terraform/modules/` | Reusable modules: network, eks, ecr, platform-addons, preview-data |
| `terraform/envs/platform/` | The shared platform cluster — the only long-lived stack |
| `policies/terraform/` | Rego policies run by conftest against `terraform plan` JSON |
| `policies/kyverno/` | Runtime admission policies (the second enforcement layer) |
| `gitops/bootstrap/` | ArgoCD app-of-apps — the single manual `kubectl apply` |
| `gitops/platform/` | Platform addons, managed declaratively |
| `gitops/previews/` | The ApplicationSet PR generator — the heart of the project |
| `app/` | Sample workload + Helm chart used to exercise the platform |
| `platform/reaper/` | TTL sweeper for orphaned environments |
| `platform/cost/` | Per-namespace cost attribution and reporting |
| `docs/` | Architecture, ADRs, runbooks, and postmortems |

## Getting started

```bash
make bootstrap
```

Then follow [BUILD_ORDER.md](BUILD_ORDER.md) — it is sequenced so that every phase
ends with something demoable.

## Compliance posture

Policies encode a subset of the NZ Information Security Manual (NZISM) and Privacy
Act 2020 obligations, chosen because they are mechanically checkable:

| Control | Where enforced | Policy |
|---|---|---|
| Data at rest encrypted | CI (Terraform plan) | `policies/terraform/encryption.rego` |
| Data residency — ap-southeast-2 only | CI (Terraform plan) | `policies/terraform/residency.rego` |
| No public storage or ingress by default | CI + admission | `policies/terraform/public_access.rego` |
| Ownership and data-classification tags | CI (Terraform plan) | `policies/terraform/tagging.rego` |
| No privileged containers / root | Admission | `policies/kyverno/pod-security.yaml` |
| Only signed images from our registry | Admission | `policies/kyverno/verify-images.yaml` |
| Preview data anonymised | Pipeline | `terraform/modules/preview-data/` |

This is a portfolio implementation, not a certified control set — see
[docs/adr/0005-compliance-scope.md](docs/adr/0005-compliance-scope.md) for what is
deliberately out of scope.
