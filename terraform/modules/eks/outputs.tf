output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 CA bundle for the API server, for building a kubeconfig."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_version" {
  description = "Kubernetes minor version actually running."
  value       = aws_eks_cluster.this.version
}

output "cluster_security_group_id" {
  description = "EKS-managed cluster security group. Dependent modules (RDS) allow ingress from this."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "IRSA OIDC provider ARN. Needed by any module creating a role for a service account."
  value       = var.enable_irsa ? aws_iam_openid_connect_provider.this[0].arn : null
}

output "oidc_provider_url" {
  description = "OIDC issuer without the https:// prefix, as IAM trust policy conditions expect it."
  value       = local.oidc_provider_url
}

output "node_role_arn" {
  description = "IAM role assumed by worker nodes, both the system group and Karpenter-provisioned."
  value       = aws_iam_role.node.arn
}

output "node_instance_profile_name" {
  description = "Instance profile for Karpenter's EC2NodeClass."
  value       = aws_iam_instance_profile.node.name
}

output "karpenter_controller_role_arn" {
  description = "Role the Karpenter controller assumes via IRSA. Set this on the karpenter ServiceAccount annotation in gitops/platform/."
  value       = var.enable_irsa ? aws_iam_role.karpenter_controller[0].arn : null
}

output "karpenter_interruption_queue_name" {
  description = "SQS queue Karpenter polls for interruption notices. Set as settings.interruptionQueue in the Helm values."
  value       = aws_sqs_queue.karpenter_interruption.name
}

output "kms_key_arn" {
  description = "KMS key encrypting Kubernetes Secrets in etcd."
  value       = aws_kms_key.secrets.arn
}
