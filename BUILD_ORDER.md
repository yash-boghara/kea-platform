# Build Order

Nine phases. Every phase ends with **something you can demo**, so the project is
never in a half-broken state you can't talk about. Rough total: 6–8 weekends.

Work on a branch per phase and merge via PR — the commit history becomes part of
the story you tell, and from Phase 4 onward the PR *is* the product.

---

## Phase 0 — Toolchain and accounts

**Goal:** everything installed, credentials working, spending alarms set.

- [ ] Install: `terraform`, `awscli`, `kubectl`, `helm`, `argocd`, `conftest`, `kyverno` CLI, `trivy`, `syft`, `cosign`, `k9s`
      → `brew bundle` from the provided `Brewfile`
- [ ] AWS account. **Do this before anything else:** a budget alarm at NZ$20 and a
      hard one at NZ$60, both emailing you.
- [ ] Register a cheap domain (~NZ$20/yr) and create a Route53 hosted zone.
      You need real DNS for the demo to land.
- [ ] Create an S3 bucket + DynamoDB table for Terraform state, in `ap-southeast-2`.
- [ ] Configure GitHub OIDC → AWS IAM role. **No long-lived AWS keys in GitHub
      secrets.** This is itself an interview talking point.

**Demo:** `aws sts get-caller-identity` from a GitHub Action, with no stored keys.

**Trap:** OIDC trust policies are fiddly. Scope the trust condition to your repo
*and* branch, or you have built a public backdoor into your AWS account.

---

## Phase 1 — Network and state foundation

**Goal:** a VPC you understand, provisioned by Terraform, with policy already on it.

- [ ] `terraform/modules/network`: VPC, 2 AZs, public + private subnets.
- [ ] **Skip the NAT Gateway.** Use VPC endpoints for S3/ECR/logs, or a single
      t4g.nano NAT instance. Write down the cost difference — it's ~US$32/mo saved,
      and it's a real FinOps decision you made.
- [ ] Remote state with locking, wired up.
- [ ] `make plan` / `make apply` targets.

**Demo:** `terraform apply` from clean, then `terraform destroy` back to zero cost.

**Write:** `docs/adr/0001-nat-strategy.md` — why you chose endpoints over a NAT GW,
including the case *against* your choice.

---

## Phase 2 — Policy gate in CI (before the cluster exists)

**Goal:** the compliance story, built early so it shapes everything after it.

- [ ] `.github/workflows/terraform.yml`: fmt → validate → plan → **conftest** → apply.
- [ ] Write four real Rego policies: encryption at rest, region residency, no public
      access, mandatory tags. Map each to an NZISM control ID in a comment.
- [ ] Unit-test the policies (`policies/tests/`). Policies without tests are a
      liability — you will get this question in an interview.
- [ ] Make the failure output *readable*: which resource, which rule, how to fix.

**Demo:** open a PR adding an unencrypted bucket. CI blocks it with a clear message
citing the control. Fix it, CI goes green.

**This is the phase most people skip.** Doing it before the cluster is what makes it
credible — it means the gate shaped the infrastructure, rather than being bolted on.

---

## Phase 3 — EKS and GitOps

**Goal:** a cluster that manages itself from a repo.

- [ ] `terraform/modules/eks`: EKS with Karpenter, IRSA enabled, private endpoints,
      control-plane logging on.
- [ ] Install ArgoCD. Then the **only** manual step forever after:
      `kubectl apply -f gitops/bootstrap/root-app.yaml`
- [ ] App-of-apps manages: external-dns, cert-manager, Kyverno, ingress-nginx,
      metrics-server.
- [ ] Karpenter on spot with a small on-demand fallback.

**Demo:** delete an addon by hand; watch ArgoCD put it back. That reconciliation
loop *is* the GitOps pitch, and seeing it beats explaining it.

**Trap:** IRSA and the Karpenter node role are the two things that will eat a full
day. Budget for it.

---

## Phase 4 — Ephemeral environments (the core)

**Goal:** PR → URL. This is the project.

- [ ] `gitops/previews/applicationset.yaml` — ArgoCD **PR generator**, watching your
      repo, templating an Application per open PR.
- [ ] Namespace per PR, labelled with PR number, author, TTL, and cost-allocation tags.
- [ ] `app/chart` — Helm chart parameterised on PR number for hostname and image tag.
- [ ] external-dns creates `pr-1234.yourdomain.nz`; cert-manager issues the cert.
- [ ] A GitHub Action comments the URL on the PR once the Application reports Healthy.
- [ ] `preview-cleanup.yml` on PR close.

**Demo:** the headline. Open a PR, watch a URL appear, click it.

**Trap:** cert-manager rate limits. Use the Let's Encrypt *staging* issuer during
development or you will be locked out for a week mid-build.

**Measure now:** start recording PR → URL time. This is your headline metric and you
want the ugly early number to contrast against.

---

## Phase 5 — Data seeding

**Goal:** environments with realistic data and no privacy exposure.

- [ ] `terraform/modules/preview-data`: schema-per-PR on one shared RDS instance
      (not an instance per PR — that is the expensive, obvious mistake).
- [ ] A seeding job that restores from an **anonymised** snapshot: names, emails,
      phone numbers, IRD-style identifiers all masked.
- [ ] Document the anonymisation as a Privacy Act 2020 control.
- [ ] Drop the schema on PR close.

**Demo:** two PRs open simultaneously, each with independent data, neither able to
see the other's.

**Why this matters:** "how do you give developers realistic data without leaking
customer data" is a question senior engineers ask because it is genuinely hard.
Having an answer puts you above the field.

---

## Phase 6 — Supply chain and admission control

**Goal:** the second and third enforcement layers.

- [ ] `build-app.yml`: build → syft SBOM → trivy scan (fail on critical) → cosign
      sign → push to ECR.
- [ ] Kyverno `verify-images`: only cosign-signed images from your ECR may run.
- [ ] Kyverno pod security: no privileged, no root, resource limits required,
      no `latest` tag.
- [ ] Run policies in `Audit` first, look at what would have broken, *then* switch
      to `Enforce`. Note what you found.

**Demo:** try to deploy an unsigned image. Admission refuses it. Show the event.

**Talking point:** three layers — CI, admission, runtime audit — and why one is not
enough. Defence in depth, concretely.

---

## Phase 7 — Observability and SLOs

**Goal:** measurement literacy, the thing that separates platform from ops.

- [ ] kube-prometheus-stack via ArgoCD.
- [ ] Define SLOs **as code** (Sloth): platform availability, provisioning latency,
      app error rate. Error budgets, not vibes.
- [ ] A Grafana dashboard: active environments, provisioning p50/p95, cost per env,
      policy violations over time.
- [ ] Alerts routed somewhere you actually read.

**Demo:** the dashboard. Screenshot it for the README.

---

## Phase 8 — Reaper and cost attribution

**Goal:** close the FinOps loop.

- [ ] `platform/reaper`: CronJob deleting namespaces past TTL, or whose PR is closed,
      or which have been idle N hours. Dry-run mode first.
- [ ] Cost allocation tags on every resource; per-namespace cost via Kubecost or
      an Athena query over the CUR.
- [ ] A weekly Slack/email report: environments created, mean lifetime, cost, waste
      reclaimed.
- [ ] The reaper emits Prometheus metrics so orphan count is on the dashboard.

**Demo:** the weekly report, with a real dollar figure you saved yourself.

**Trap:** write the dry-run mode *first* and run it for a week before enabling
deletion. A reaper bug that deletes a live namespace is a bad afternoon — and if you
hit one, that's a postmortem worth writing up honestly.

---

## Phase 9 — Packaging (do not skip)

This phase is worth more per hour than Phases 1–8. The work is done; this is what
makes it *legible*.

- [ ] **README metrics table** filled in with real measured numbers.
- [ ] **Architecture diagram** — a real one, exported as PNG, embedded in the README.
- [ ] **3-minute Loom.** PR → URL → policy block → teardown. Most candidates link a
      repo nobody opens; a video gets watched.
- [ ] **Three postmortems** in `docs/postmortems/` from things that actually broke
      during the build. Honest ones. This is the single most differentiating artifact
      in the whole repo.
- [ ] **ADRs** for the five decisions where you rejected a reasonable alternative.
- [ ] **Cost writeup** — what it runs at and how you got it there.
- [ ] **A "what I'd do differently" section.** Self-awareness reads as seniority.

---

## Optional Phase 10 — differentiators

Pick at most one. A finished nine-phase project beats a sprawling eleven-phase one.

- **Multi-cloud slice:** deploy one component to Azure and write the comparison.
  In NZ this genuinely doubles the roles you're eligible for.
- **AIOps touch:** on pipeline failure, an agent reads the logs and comments a
  suspected root cause on the PR. Small scope, very current.
- **Chaos day:** run a fault-injection experiment against the platform itself and
  publish the resilience scorecard.

---

## Sequencing notes

- Phases 2, 6 and 7 are the ones candidates skip and interviewers probe. They are
  where your differentiation actually lives.
- Do not start Phase 9 last-minute. Write the ADRs and postmortems *as they happen* —
  reconstructed ones read as reconstructed.
- Certifications pair well with the timeline: CKA around Phase 4, AWS SAA around
  Phase 8. NZ postings list both explicitly.
- If you run out of time, ship Phases 0–4 plus 9. A polished, well-documented core
  beats an undocumented sprawl every time.
