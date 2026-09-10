import os
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

AGENT_ROOT = Path(__file__).resolve().parents[1]
if str(AGENT_ROOT) not in sys.path:
    sys.path.append(str(AGENT_ROOT))

import local_runner


class LocalRunnerTests(unittest.TestCase):
    def test_openai_credentials_can_use_local_env(self):
        with patch.dict(
            os.environ,
            {
                "OPENAI_API_KEY": "test-key",
                "OPENAI_BASE_URL": "http://localhost:9999/v1",
                "OPENAI_MODEL_ID": "local-model",
                "OPENAI_CREDENTIAL_PROVIDER_NAME": "",
            },
            clear=False,
        ):
            credentials = local_runner.get_local_openai_credentials()

        self.assertEqual(credentials["api_key"], "test-key")
        self.assertEqual(credentials["base_url"], "http://localhost:9999/v1")
        self.assertEqual(credentials["model_id"], "local-model")

    def test_local_runtime_tools_enable_opentofu_guidance_without_remote_only_tools(self):
        runtime_tools = local_runner.create_local_runtime_tools()

        self.assertIsNone(runtime_tools.gateway)
        self.assertIsNotNone(runtime_tools.opentofu)
        self.assertIsNone(runtime_tools.handoff_to_user)
        self.assertIsNone(runtime_tools.create_pull_request)
        self.assertIsNotNone(runtime_tools.file_read)
        self.assertIsNotNone(runtime_tools.file_write)
        self.assertIsNotNone(runtime_tools.terraform_validate)

    def test_core_eval_prompt_excludes_removed_eval_agents(self):
        self.assertIn("engineer_agent", local_runner.CORE_EVAL_PROMPT)
        self.assertIn("reviewer_agent", local_runner.CORE_EVAL_PROMPT)
        self.assertIn("Do not call architect", local_runner.CORE_EVAL_PROMPT)
        self.assertIn("security", local_runner.CORE_EVAL_PROMPT)
        self.assertIn("FinOps", local_runner.CORE_EVAL_PROMPT)
        self.assertIn("DevOps", local_runner.CORE_EVAL_PROMPT)

    def test_local_core_eval_has_terrashark_skill_available(self):
        self.assertTrue((local_runner.TERRASHARK_SKILL_DIR / "SKILL.md").is_file())
        source = Path(local_runner.__file__).read_text(encoding="utf-8")
        self.assertIn("plugins=[create_terrashark_plugin()]", source)

    def test_workspace_files_lists_relative_files(self):
        with TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "main.tf").write_text("terraform {}\n", encoding="utf-8")
            (root / ".git").mkdir()
            (root / ".git" / "config").write_text("", encoding="utf-8")

            self.assertEqual(local_runner.workspace_files(root), ["main.tf"])

    def test_parse_args_allows_dry_run_without_prompt(self):
        with patch("sys.argv", ["local_runner.py", "--dry-run"]):
            args = local_runner.parse_args()

        self.assertTrue(args.dry_run)
        self.assertIsNone(args.prompt)
        self.assertIsNone(args.prompt_file)

    def test_load_env_file_does_not_override_existing_env(self):
        with TemporaryDirectory() as temp:
            env_file = Path(temp) / ".env"
            env_file.write_text("OPENAI_API_KEY=file-key\nOPENAI_MODEL_ID=file-model\n", encoding="utf-8")
            with patch.dict(os.environ, {"OPENAI_API_KEY": "existing-key"}, clear=False):
                loaded = local_runner.load_env_file(env_file)

                self.assertEqual(os.environ["OPENAI_API_KEY"], "existing-key")
                self.assertEqual(os.environ["OPENAI_MODEL_ID"], "file-model")
        self.assertEqual(loaded, ["OPENAI_MODEL_ID"])

    def test_eval_prompt_limits_engineer_passes(self):
        root = Path(__file__).resolve().parents[2]
        prompt_source = (root / "scripts" / "eval-iac-eval-chat.py").read_text(encoding="utf-8")

        self.assertIn("at most 3 total implementation/fix passes", prompt_source)


if __name__ == "__main__":
    unittest.main()
