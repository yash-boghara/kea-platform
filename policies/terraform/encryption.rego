# NZISM control reference: 17.1 (Cryptographic fundamentals),
# 22.1 (Data at rest protection). Privacy Act 2020 IPP 5 (storage security).
#
# Run against `terraform show -json tfplan` via conftest.
# Failure messages name the resource, the rule and the fix — a policy engine
# that only says "denied" trains people to disable it.

package terraform.encryption

import rego.v1

# `contains` makes this a partial SET. Writing `resources[r] if { ... }` instead
# defines a partial OBJECT whose values are `true`, so `some r in resources`
# would iterate booleans rather than resources — which is exactly the bug the
# unit tests caught here.
resources contains r if {
	some change in input.resource_changes
	some action in change.change.actions
	action in {"create", "update"}
	r := change
}

# --- S3 -----------------------------------------------------------------

deny contains msg if {
	some r in resources
	r.type == "aws_s3_bucket"
	not sse_configured(r.address)
	msg := sprintf(
		"[NZISM 22.1] S3 bucket '%s' has no server-side encryption. Add an aws_s3_bucket_server_side_encryption_configuration resource targeting it, using aws:kms.",
		[r.address],
	)
}

sse_configured(bucket_address) if {
	some r in resources
	r.type == "aws_s3_bucket_server_side_encryption_configuration"
	contains(r.change.after.bucket, trim_prefix(bucket_address, "aws_s3_bucket."))
}

# --- RDS ----------------------------------------------------------------

# object.get with a `false` default is load-bearing, not style. Writing
# `r.change.after.storage_encrypted != true` looks equivalent but is undefined
# when the attribute is absent, so the rule never fires and an unencrypted
# database passes. Absent must be treated as insecure: fail closed.
deny contains msg if {
	some r in resources
	r.type in ["aws_db_instance", "aws_rds_cluster"]
	object.get(r.change.after, "storage_encrypted", false) != true
	msg := sprintf(
		"[NZISM 22.1] Database '%s' is not encrypted at rest. Set storage_encrypted = true and supply a kms_key_id.",
		[r.address],
	)
}

# --- EBS ----------------------------------------------------------------

deny contains msg if {
	some r in resources
	r.type == "aws_ebs_volume"
	object.get(r.change.after, "encrypted", false) != true
	msg := sprintf(
		"[NZISM 22.1] EBS volume '%s' is not encrypted. Set encrypted = true.",
		[r.address],
	)
}

# --- ECR ----------------------------------------------------------------

deny contains msg if {
	some r in resources
	r.type == "aws_ecr_repository"
	not r.change.after.encryption_configuration
	msg := sprintf(
		"[NZISM 22.1] ECR repository '%s' has no encryption_configuration block.",
		[r.address],
	)
}
