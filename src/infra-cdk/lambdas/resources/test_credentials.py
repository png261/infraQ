import importlib.util
import os
from pathlib import Path
from unittest import TestCase, main
from unittest.mock import Mock, patch


def load_index_module():
    os.environ.setdefault("TABLE_NAME", "test-table")
    os.environ.setdefault("CODEBUILD_PROJECT_NAME", "test-project")
    os.environ.setdefault("STACK_NAME_BASE", "test-stack")
    os.environ.setdefault("AWS_EC2_METADATA_DISABLED", "true")
    module_path = Path(__file__).with_name("index.py")
    spec = importlib.util.spec_from_file_location("resources_index_under_test_credentials", module_path)
    module = importlib.util.module_from_spec(spec)
    with patch("boto3.resource") as resource, patch("boto3.client") as client:
        resource.return_value.Table.return_value = Mock()
        client.return_value = Mock()
        assert spec.loader is not None
        spec.loader.exec_module(module)
    return module


class CredentialManagementTests(TestCase):
    def setUp(self):
        self.module = load_index_module()

    def test_delete_credential_removes_related_state_backends_and_updates_active_credential(self):
        self.module._credential_store = Mock(
            return_value={
                "version": 2,
                "activeCredentialId": "cred-1",
                "credentials": {
                    "cred-1": {"credentialId": "cred-1", "accessKeyId": "AKIA123456789012", "secretAccessKey": "secret"},
                    "cred-2": {"credentialId": "cred-2", "accessKeyId": "AKIA987654321098", "secretAccessKey": "secret"},
                },
            }
        )
        self.module._list_state_backends = Mock(
            return_value=[
                {"backendId": "backend-1", "credentialId": "cred-1"},
                {"backendId": "backend-2", "credentialId": "cred-2"},
                {"backendId": "backend-3", "credentialId": "cred-1"},
            ]
        )
        self.module._delete_state_backend = Mock(
            side_effect=[
                {"backendId": "backend-1", "deletedScans": 1, "deletedDriftGuards": 0, "deletedTerraformJobs": 0},
                {"backendId": "backend-3", "deletedScans": 0, "deletedDriftGuards": 1, "deletedTerraformJobs": 1},
            ]
        )
        self.module.secretsmanager = Mock()

        result = self.module._delete_aws_credential("user-1", "cred-1")

        self.assertEqual(result["credentialId"], "cred-1")
        self.assertEqual(result["deletedBackendCount"], 2)
        self.assertEqual([item["backendId"] for item in result["deletedBackends"]], ["backend-1", "backend-3"])
        self.assertEqual(
            [call.args[1] for call in self.module._delete_state_backend.call_args_list],
            ["backend-1", "backend-3"],
        )
        secret_string = self.module.secretsmanager.put_secret_value.call_args.kwargs["SecretString"]
        self.assertIn('"activeCredentialId": "cred-2"', secret_string)
        self.assertNotIn('"cred-1"', secret_string)

    def test_create_state_backend_returns_without_synchronous_graph_generation(self):
        self.module._credential_store = Mock(
            return_value={
                "version": 2,
                "activeCredentialId": "cred-1",
                "credentials": {
                    "cred-1": {
                        "credentialId": "cred-1",
                        "name": "Smoke local AWS credential",
                        "accessKeyId": "AKIA123456789012",
                        "secretAccessKey": "secret",
                    },
                },
            }
        )
        self.module._state_backend_id = Mock(return_value="backend-1")
        self.module._attach_backend_graph = Mock()
        self.module.table = Mock()

        result = self.module._create_state_backend(
            "user-1",
            {
                "name": "Smoke vpc-terraform",
                "bucket": "png261-state-bucket",
                "key": "smoke/vpc-terraform/terraform.tfstate",
                "region": "ap-southeast-1",
                "service": "ec2",
                "credentialId": "cred-1",
                "repository": {
                    "fullName": "png261/vpc-terraform",
                    "owner": "png261",
                    "name": "vpc-terraform",
                    "defaultBranch": "main",
                    "url": "https://github.com/png261/vpc-terraform",
                },
            },
        )

        self.assertEqual(result["backendId"], "backend-1")
        self.assertEqual(result["bucket"], "png261-state-bucket")
        self.assertEqual(result["credentialId"], "cred-1")
        self.module.table.put_item.assert_called_once()
        self.module._attach_backend_graph.assert_not_called()

    def test_backend_graph_url_generates_graph_on_demand_when_missing(self):
        self.module._get_state_backend = Mock(
            return_value={
                "backendId": "backend-1",
                "name": "Smoke vpc-terraform",
                "bucket": "png261-state-bucket",
                "key": "smoke/vpc-terraform/terraform.tfstate",
                "region": "ap-southeast-1",
                "service": "ec2",
                "credentialId": "cred-1",
            }
        )
        self.module._attach_backend_graph = Mock(
            return_value={
                "backendId": "backend-1",
                "graphBucket": "graph-bucket",
                "graphKey": "resource-graphs/user-1/backend-1/latest.html",
                "graphGeneratedAt": "2026-05-18T02:30:00Z",
                "graphResourceCount": 27,
            }
        )
        self.module.s3 = Mock()
        self.module.s3.generate_presigned_url.return_value = "https://example.com/graph.html"

        result = self.module._backend_graph_url("user-1", "backend-1")

        self.assertEqual(result["url"], "https://example.com/graph.html")
        self.assertEqual(result["backendId"], "backend-1")
        self.assertEqual(result["graphResourceCount"], 27)
        self.module._attach_backend_graph.assert_called_once()


if __name__ == "__main__":
    main()
