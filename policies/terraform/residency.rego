# Data residency. New Zealand government and regulated-sector workloads
# increasingly require data to stay in-country or in an approved jurisdiction.
#
# AWS ap-southeast-2 (Sydney) is the pragmatic default; the NZ region
# (ap-southeast-6) is the in-country option. Both are allowed here; anything
# else is denied. See docs/adr/0002-region-choice.md for the trade-off —
# the NZ region has fewer services and higher cost, which is exactly the kind
# of decision worth being able to defend in an interview.

package terraform.residency

import rego.v1

allowed_regions := {"ap-southeast-2", "ap-southeast-6"}

# Provider-level check.
deny contains msg if {
	some config in input.configuration.provider_config
	config.name == "aws"
	region := config.expressions.region.constant_value
	not region in allowed_regions
	msg := sprintf(
		"[Data residency] Provider configured for region '%s'. Allowed: %v. NZ data must remain in-country or in the approved AU region.",
		[region, allowed_regions],
	)
}

# Catch resources that pin a region explicitly, e.g. replication targets,
# which are the usual way data quietly leaves the jurisdiction.
deny contains msg if {
	some change in input.resource_changes
	change.type == "aws_s3_bucket_replication_configuration"
	some rule in change.change.after.rule
	some dest in rule.destination
	not destination_in_allowed_region(dest.bucket)
	msg := sprintf(
		"[Data residency] S3 replication from '%s' targets a bucket outside the approved regions.",
		[change.address],
	)
}

destination_in_allowed_region(arn) if {
	some region in allowed_regions
	contains(arn, region)
}
