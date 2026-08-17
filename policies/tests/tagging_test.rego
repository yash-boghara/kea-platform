# Policies without tests are a liability: they drift, they get disabled after a
# false positive, and you cannot answer "how do you know the policy works?"
#
# Run: conftest verify -p policies/

package terraform.tagging_test

import data.terraform.tagging
import rego.v1

valid_tags := {
	"Owner": "platform-team",
	"Environment": "preview",
	"CostCentre": "eng-001",
	"DataClassification": "internal",
	"ManagedBy": "terraform",
}

test_fully_tagged_resource_allowed if {
	count(tagging.deny) == 0 with input as {"resource_changes": [{
		"address": "aws_s3_bucket.good",
		"type": "aws_s3_bucket",
		"change": {"actions": ["create"], "after": {"tags": valid_tags}},
	}]}
}

test_missing_owner_denied if {
	count(tagging.deny) == 1 with input as {"resource_changes": [{
		"address": "aws_s3_bucket.bad",
		"type": "aws_s3_bucket",
		"change": {"actions": ["create"], "after": {"tags": object.remove(valid_tags, ["Owner"])}},
	}]}
}

test_invalid_classification_denied if {
	count(tagging.deny) == 1 with input as {"resource_changes": [{
		"address": "aws_s3_bucket.bad",
		"type": "aws_s3_bucket",
		"change": {"actions": ["create"], "after": {"tags": object.union(valid_tags, {"DataClassification": "top-secret"})}},
	}]}
}

test_untaggable_type_skipped if {
	count(tagging.deny) == 0 with input as {"resource_changes": [{
		"address": "aws_s3_bucket_public_access_block.this",
		"type": "aws_s3_bucket_public_access_block",
		"change": {"actions": ["create"], "after": {}},
	}]}
}

test_delete_action_skipped if {
	count(tagging.deny) == 0 with input as {"resource_changes": [{
		"address": "aws_s3_bucket.going",
		"type": "aws_s3_bucket",
		"change": {"actions": ["delete"], "after": null},
	}]}
}
