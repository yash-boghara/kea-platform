# Karpenter's AWS-side prerequisites.
#
# The Karpenter *controller* is installed as an ArgoCD Application in
# gitops/platform/; what lives here is everything it cannot create for itself:
# an IAM role it can assume via IRSA, an instance profile for the nodes it
# launches, and the SQS queue that tells it when a spot instance is about to be
# reclaimed.
#
# Without the interruption queue, Karpenter learns about a spot reclaim when the
# node disappears. With it, Karpenter gets the two-minute warning and drains the
# node first. On a cluster running preview environments on spot, that is the
# difference between a graceful migration and reviewers seeing 502s.

locals {
  karpenter_namespace       = "kube-system"
  karpenter_service_account = "karpenter"
}

# --- Controller role (IRSA) ---------------------------------------------

data "aws_iam_policy_document" "karpenter_assume_role" {
  count = var.enable_irsa ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this[0].arn]
    }

    # Scope the trust to exactly one ServiceAccount in one namespace. Without
    # both conditions, ANY pod in the cluster could assume this role — and this
    # role can create EC2 instances.
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${local.karpenter_namespace}:${local.karpenter_service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "karpenter_controller" {
  count = var.enable_irsa ? 1 : 0

  name               = "${var.name}-karpenter"
  assume_role_policy = data.aws_iam_policy_document.karpenter_assume_role[0].json
  tags               = var.tags
}

data "aws_iam_policy_document" "karpenter_controller" {
  # Read-only discovery: which instance types exist, what they cost, which
  # subnets and AMIs match the NodeClass selectors.
  statement {
    sid    = "Discovery"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeImages",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeAvailabilityZones",
      "pricing:GetProducts",
      "ssm:GetParameter",
      "eks:DescribeCluster",
    ]
    resources = ["*"]
  }

  # Provisioning. Creation is unscoped because the resources do not exist yet;
  # deletion below is tag-scoped so Karpenter can only terminate what it owns.
  statement {
    sid    = "Provision"
    effect = "Allow"
    actions = [
      "ec2:CreateLaunchTemplate",
      "ec2:CreateFleet",
      "ec2:RunInstances",
      "ec2:CreateTags",
    ]
    resources = ["*"]
  }

  # The important boundary: Karpenter may only terminate instances carrying its
  # own discovery tag for THIS cluster. A bug or a compromised controller cannot
  # reach into unrelated infrastructure.
  statement {
    sid    = "TerminateOwnedInstancesOnly"
    effect = "Allow"
    actions = [
      "ec2:TerminateInstances",
      "ec2:DeleteLaunchTemplate",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/karpenter.sh/discovery"
      values   = [var.name]
    }
  }

  # Karpenter passes the node role to the instances it launches. Scoped to that
  # one role: iam:PassRole on "*" would let it attach any role in the account to
  # an instance it controls, which is a full account takeover primitive.
  statement {
    sid       = "PassNodeRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.node.arn]
  }

  statement {
    sid    = "InstanceProfile"
    effect = "Allow"
    actions = [
      "iam:GetInstanceProfile",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "InterruptionQueue"
    effect = "Allow"
    actions = [
      "sqs:DeleteMessage",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage",
    ]
    resources = [aws_sqs_queue.karpenter_interruption.arn]
  }
}

resource "aws_iam_role_policy" "karpenter_controller" {
  count = var.enable_irsa ? 1 : 0

  name   = "${var.name}-karpenter"
  role   = aws_iam_role.karpenter_controller[0].id
  policy = data.aws_iam_policy_document.karpenter_controller.json
}

# --- Node instance profile ---------------------------------------------

resource "aws_iam_instance_profile" "node" {
  name = "${var.name}-node"
  role = aws_iam_role.node.name
  tags = var.tags
}

# --- Interruption queue -------------------------------------------------

resource "aws_sqs_queue" "karpenter_interruption" {
  name = "${var.name}-karpenter-interruption"

  # Interruption notices are only actionable inside the two-minute warning
  # window; a message older than five minutes is worthless.
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true

  tags = merge(var.tags, { Name = "${var.name}-karpenter-interruption" })
}

data "aws_iam_policy_document" "karpenter_interruption" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.karpenter_interruption.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "sqs.amazonaws.com"]
    }
  }
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  queue_url = aws_sqs_queue.karpenter_interruption.url
  policy    = data.aws_iam_policy_document.karpenter_interruption.json
}

# Four event sources, each a different way a node can go away:
#   spot_interruption  - spot reclaim, two-minute warning
#   rebalance          - AWS predicts elevated reclaim risk, no deadline
#   instance_state     - the instance is stopping or terminating
#   scheduled_change   - AWS maintenance on the underlying hardware
locals {
  karpenter_events = {
    spot_interruption = {
      source      = "aws.ec2"
      detail_type = "EC2 Spot Instance Interruption Warning"
    }
    rebalance = {
      source      = "aws.ec2"
      detail_type = "EC2 Instance Rebalance Recommendation"
    }
    instance_state = {
      source      = "aws.ec2"
      detail_type = "EC2 Instance State-change Notification"
    }
    scheduled_change = {
      source      = "aws.health"
      detail_type = "AWS Health Event"
    }
  }
}

resource "aws_cloudwatch_event_rule" "karpenter" {
  for_each = local.karpenter_events

  name        = "${var.name}-karpenter-${each.key}"
  description = "Karpenter interruption handling: ${each.value.detail_type}"

  event_pattern = jsonencode({
    source        = [each.value.source]
    "detail-type" = [each.value.detail_type]
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "karpenter" {
  for_each = local.karpenter_events

  rule      = aws_cloudwatch_event_rule.karpenter[each.key].name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.karpenter_interruption.arn
}

# --- Discovery tags -----------------------------------------------------
#
# Karpenter finds the security group to attach to new nodes by this tag. The
# cluster security group is created by EKS, so it is tagged here rather than in
# the network module.

resource "aws_ec2_tag" "cluster_sg_discovery" {
  resource_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  key         = "karpenter.sh/discovery"
  value       = var.name
}
