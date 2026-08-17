package terraform.encryption_test

import data.terraform.encryption
import rego.v1

# --- S3 -----------------------------------------------------------------

test_bucket_with_sse_allowed if {
	count(encryption.deny) == 0 with input as {"resource_changes": [
		{
			"address": "aws_s3_bucket.data",
			"type": "aws_s3_bucket",
			"change": {"actions": ["create"], "after": {}},
		},
		{
			"address": "aws_s3_bucket_server_side_encryption_configuration.data",
			"type": "aws_s3_bucket_server_side_encryption_configuration",
			"change": {"actions": ["create"], "after": {"bucket": "data"}},
		},
	]}
}

test_bucket_without_sse_denied if {
	count(encryption.deny) == 1 with input as {"resource_changes": [{
		"address": "aws_s3_bucket.data",
		"type": "aws_s3_bucket",
		"change": {"actions": ["create"], "after": {}},
	}]}
}

# --- RDS ----------------------------------------------------------------

test_encrypted_rds_allowed if {
	count(encryption.deny) == 0 with input as {"resource_changes": [{
		"address": "aws_db_instance.previews",
		"type": "aws_db_instance",
		"change": {"actions": ["create"], "after": {"storage_encrypted": true}},
	}]}
}

test_unencrypted_rds_denied if {
	count(encryption.deny) == 1 with input as {"resource_changes": [{
		"address": "aws_db_instance.previews",
		"type": "aws_db_instance",
		"change": {"actions": ["create"], "after": {"storage_encrypted": false}},
	}]}
}

# A missing attribute must fail closed. Absent is not the same as false in Rego,
# and getting this wrong is how a policy silently passes everything.
test_rds_missing_encryption_attribute_denied if {
	count(encryption.deny) == 1 with input as {"resource_changes": [{
		"address": "aws_db_instance.previews",
		"type": "aws_db_instance",
		"change": {"actions": ["create"], "after": {}},
	}]}
}

# --- EBS ----------------------------------------------------------------

test_unencrypted_ebs_denied if {
	count(encryption.deny) == 1 with input as {"resource_changes": [{
		"address": "aws_ebs_volume.scratch",
		"type": "aws_ebs_volume",
		"change": {"actions": ["create"], "after": {"encrypted": false}},
	}]}
}

# --- ECR ----------------------------------------------------------------

test_ecr_without_encryption_config_denied if {
	count(encryption.deny) == 1 with input as {"resource_changes": [{
		"address": "aws_ecr_repository.app",
		"type": "aws_ecr_repository",
		"change": {"actions": ["create"], "after": {}},
	}]}
}

# --- Action filtering ---------------------------------------------------

test_destroy_action_ignored if {
	count(encryption.deny) == 0 with input as {"resource_changes": [{
		"address": "aws_db_instance.old",
		"type": "aws_db_instance",
		"change": {"actions": ["delete"], "after": null},
	}]}
}
