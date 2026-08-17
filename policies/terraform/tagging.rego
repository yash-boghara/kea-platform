# Tagging is the foundation of cost attribution. Without it, the FinOps
# reporting in platform/cost/ cannot tell you what a preview environment costs,
# and the reaper cannot tell what is safe to delete.
#
# Treat untagged resources as a hard failure, not a warning. Warnings get ignored.

package terraform.tagging

import rego.v1

required_tags := {
	"Owner",             # who to ask before deleting
	"Environment",       # platform | preview | shared
	"CostCentre",        # cost allocation
	"DataClassification", # public | internal | confidential — drives other controls
	"ManagedBy",         # always "terraform"; catches ClickOps drift
}

# Resource types that genuinely cannot carry tags.
untaggable := {
	"aws_s3_bucket_server_side_encryption_configuration",
	"aws_s3_bucket_public_access_block",
	"aws_iam_role_policy_attachment",
	"aws_route_table_association",
}

deny contains msg if {
	some change in input.resource_changes
	change.change.actions[_] in ["create", "update"]
	startswith(change.type, "aws_")
	not change.type in untaggable
	tags := object.get(change.change.after, "tags", {})
	missing := required_tags - {k | some k, _ in tags}
	count(missing) > 0
	msg := sprintf(
		"[Tagging] Resource '%s' is missing required tags: %v. Add them via the provider default_tags block or the module's tags variable.",
		[change.address, missing],
	)
}

# DataClassification must be a known value — a free-text tag is not a control.
deny contains msg if {
	some change in input.resource_changes
	classification := change.change.after.tags.DataClassification
	not classification in {"public", "internal", "confidential"}
	msg := sprintf(
		"[Tagging] Resource '%s' has DataClassification '%s'. Must be one of: public, internal, confidential.",
		[change.address, classification],
	)
}
