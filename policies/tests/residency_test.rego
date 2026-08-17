package terraform.residency_test

import data.terraform.residency
import rego.v1

provider_in(region) := {"configuration": {"provider_config": {"aws": {
	"name": "aws",
	"expressions": {"region": {"constant_value": region}},
}}}}

test_sydney_allowed if {
	count(residency.deny) == 0 with input as provider_in("ap-southeast-2")
}

test_nz_region_allowed if {
	count(residency.deny) == 0 with input as provider_in("ap-southeast-6")
}

test_us_east_denied if {
	count(residency.deny) == 1 with input as provider_in("us-east-1")
}

# The likely real-world mistake: someone copies a module that defaults to
# eu-west-1 and nobody notices until the data is already offshore.
test_eu_denied if {
	count(residency.deny) == 1 with input as provider_in("eu-west-1")
}

# Replication is how data leaves the jurisdiction without the provider region
# ever changing — the case the provider-level check alone would miss.
test_replication_to_disallowed_region_denied if {
	count(residency.deny) == 1 with input as {"resource_changes": [{
		"address": "aws_s3_bucket_replication_configuration.offsite",
		"type": "aws_s3_bucket_replication_configuration",
		"change": {"actions": ["create"], "after": {"rule": [{"destination": [{"bucket": "arn:aws:s3:::backups-us-east-1"}]}]}},
	}]}
}

test_replication_within_allowed_region_ok if {
	count(residency.deny) == 0 with input as {"resource_changes": [{
		"address": "aws_s3_bucket_replication_configuration.dr",
		"type": "aws_s3_bucket_replication_configuration",
		"change": {"actions": ["create"], "after": {"rule": [{"destination": [{"bucket": "arn:aws:s3:::backups-ap-southeast-2"}]}]}},
	}]}
}
