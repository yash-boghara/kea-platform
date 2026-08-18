# ADR 0004 — What Terraform owns vs what ArgoCD owns

**Status:** Accepted
**Date:** 2026-08-18
**Phase:** 3

## Context

Both Terraform and ArgoCD can create Kubernetes objects. Terraform has a
`kubernetes` provider and a `helm` provider; ArgoCD can manage anything with a
manifest. Without a stated rule, the boundary drifts — some addons end up in
Terraform because that is where the cluster was created, others in Git because
that is where the app lives, and nobody can answer "where do I change this?"

The failure mode is concrete: an addon installed by the Terraform Helm provider
is invisible to ArgoCD, so drift is undetected, and a `terraform destroy` on
unrelated infrastructure can quietly take it out.

## Decision

**Terraform owns what a cluster cannot create for itself. Git owns everything
running inside it.**

In practice:

| Terraform | ArgoCD |
|---|---|
| VPC, subnets, routing | Ingress controllers |
| EKS control plane, node groups | cert-manager, external-dns |
| IAM roles, IRSA OIDC provider | Kyverno + its policies |
| KMS keys | Karpenter controller + NodePools |
| SQS interruption queue, EventBridge | Prometheus, Grafana |
| ECR repositories, RDS | Preview environments |
| **EKS-managed addons** (vpc-cni, kube-proxy, CoreDNS) | Everything installed by Helm |

## The one deliberate exception

EKS-managed addons are in Terraform despite running in the cluster. They are
control-plane resources managed through the EKS API, not the Kubernetes API —
`aws eks describe-addon`, not `kubectl get`. Their version compatibility is tied
to the control plane version, which Terraform owns.

CoreDNS is the awkward case: it is an EKS addon but also an ordinary Deployment.
It stays in Terraform because its configuration must change in lockstep with the
node group taint, and splitting those across two systems creates a
bootstrap ordering problem.

## The bootstrap seam

Exactly one manual step exists:

```
kubectl apply -f gitops/bootstrap/root-app.yaml
```

Terraform builds the cluster; that command hands it to ArgoCD; ArgoCD does the
rest. Terraform never installs ArgoCD Applications, and ArgoCD never creates AWS
resources.

Karpenter shows the seam clearly. Its IAM role, instance profile and interruption
queue are Terraform, because they are AWS resources. Its controller Deployment
and its NodePool CRDs are ArgoCD, because they are Kubernetes objects. The two
halves are joined by an annotation carrying the role ARN.

## Consequences

**Good**
- One answer to "where do I change this?" — is it an AWS resource or a
  Kubernetes object?
- Cluster contents are continuously reconciled; drift self-heals
- `terraform destroy` cannot silently remove an in-cluster component
- Terraform state stays small, so plans stay fast and reviewable

**Bad**
- Values must cross the seam. The Karpenter role ARN is a Terraform output that
  has to reach a Helm value in Git, currently by hand. A follow-up could push
  outputs to SSM Parameter Store and read them with an ArgoCD plugin.
- Two systems to learn, and two places to look during an incident
- Ordering is implicit: ArgoCD Applications fail until the IAM they reference
  exists. Recoverable — ArgoCD retries — but confusing the first time.

## Revisit when

Crossing the seam by hand becomes error-prone (roughly: more than about five
values), at which point pushing Terraform outputs into SSM and reading them from
ArgoCD is worth the extra machinery.
