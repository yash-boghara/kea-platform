package terraform.public_access_test

import data.terraform.public_access
import rego.v1

all_blocked := {
	"bucket": "data",
	"block_public_acls": true,
	"block_public_policy": true,
	"ignore_public_acls": true,
	"restrict_public_buckets": true,
}

bucket_resource := {
	"address": "aws_s3_bucket.data",
	"type": "aws_s3_bucket",
	"change": {"actions": ["create"], "after": {}},
}

pab_resource(settings) := {
	"address": "aws_s3_bucket_public_access_block.data",
	"type": "aws_s3_bucket_public_access_block",
	"change": {"actions": ["create"], "after": settings},
}

test_fully_blocked_bucket_allowed if {
	count(public_access.deny) == 0 with input as {"resource_changes": [bucket_resource, pab_resource(all_blocked)]}
}

test_one_setting_false_denied if {
	count(public_access.deny) == 1 with input as {"resource_changes": [
		bucket_resource,
		pab_resource(object.union(all_blocked, {"block_public_policy": false})),
	]}
}

# Four independent findings, not one. Each is separately actionable.
test_all_settings_false_gives_four_findings if {
	count(public_access.deny) == 4 with input as {"resource_changes": [
		bucket_resource,
		pab_resource({
			"bucket": "data",
			"block_public_acls": false,
			"block_public_policy": false,
			"ignore_public_acls": false,
			"restrict_public_buckets": false,
		}),
	]}
}

# A bucket with no public access block at all is the more dangerous case: the
# absence of a control looks like nothing rather than like a misconfiguration.
test_bucket_with_no_pab_denied if {
	count(public_access.deny) == 1 with input as {"resource_changes": [bucket_resource]}
}

# --- RDS ----------------------------------------------------------------

test_public_rds_denied if {
	count(public_access.deny) == 1 with input as {"resource_changes": [{
		"address": "aws_db_instance.previews",
		"type": "aws_db_instance",
		"change": {"actions": ["create"], "after": {"publicly_accessible": true}},
	}]}
}

# --- Security groups ----------------------------------------------------

test_world_open_ssh_denied if {
	count(public_access.deny) == 1 with input as {"resource_changes": [{
		"address": "aws_security_group_rule.ssh",
		"type": "aws_security_group_rule",
		"change": {"actions": ["create"], "after": {
			"type": "ingress",
			"from_port": 22,
			"cidr_blocks": ["0.0.0.0/0"],
		}},
	}]}
}

test_world_open_https_allowed if {
	count(public_access.deny) == 0 with input as {"resource_changes": [{
		"address": "aws_security_group_rule.https",
		"type": "aws_security_group_rule",
		"change": {"actions": ["create"], "after": {
			"type": "ingress",
			"from_port": 443,
			"cidr_blocks": ["0.0.0.0/0"],
		}},
	}]}
}

test_ssh_from_private_cidr_allowed if {
	count(public_access.deny) == 0 with input as {"resource_changes": [{
		"address": "aws_security_group_rule.ssh_internal",
		"type": "aws_security_group_rule",
		"change": {"actions": ["create"], "after": {
			"type": "ingress",
			"from_port": 22,
			"cidr_blocks": ["10.20.0.0/16"],
		}},
	}]}
}
