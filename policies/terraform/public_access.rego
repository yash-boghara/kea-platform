# NZISM 19.1 (Network segmentation), 16.1 (Access control).
# The classic breach vector: storage or a database reachable from the internet
# because a default was left alone.

package terraform.public_access

import rego.v1

deny contains msg if {
	some change in input.resource_changes
	change.type == "aws_s3_bucket_public_access_block"
	settings := change.change.after
	some field in ["block_public_acls", "block_public_policy", "ignore_public_acls", "restrict_public_buckets"]

	# Default false, not a bare lookup: an absent setting is undefined in Rego,
	# which would skip the rule entirely and let a partially-configured block
	# through. See the same trap in encryption.rego.
	object.get(settings, field, false) != true
	msg := sprintf(
		"[NZISM 19.1] '%s' sets %s = false. All four public access block settings must be true.",
		[change.address, field],
	)
}

# A bucket with no public access block at all is worse than one configured badly.
deny contains msg if {
	some change in input.resource_changes
	change.type == "aws_s3_bucket"
	not has_public_access_block(change.address)
	msg := sprintf(
		"[NZISM 19.1] S3 bucket '%s' has no aws_s3_bucket_public_access_block. Add one with all four settings true.",
		[change.address],
	)
}

has_public_access_block(bucket_address) if {
	some change in input.resource_changes
	change.type == "aws_s3_bucket_public_access_block"
	contains(change.change.after.bucket, trim_prefix(bucket_address, "aws_s3_bucket."))
}

deny contains msg if {
	some change in input.resource_changes
	change.type in ["aws_db_instance", "aws_rds_cluster_instance"]
	change.change.after.publicly_accessible == true
	msg := sprintf(
		"[NZISM 19.1] Database '%s' is publicly accessible. Set publicly_accessible = false and reach it through the VPC.",
		[change.address],
	)
}

# Security groups open to the world on anything other than 80/443.
deny contains msg if {
	some change in input.resource_changes
	change.type == "aws_security_group_rule"
	after := change.change.after
	after.type == "ingress"
	"0.0.0.0/0" in after.cidr_blocks
	not after.from_port in [80, 443]
	msg := sprintf(
		"[NZISM 19.1] Security group rule '%s' allows 0.0.0.0/0 on port %d. Only 80 and 443 may be world-open.",
		[change.address, after.from_port],
	)
}
