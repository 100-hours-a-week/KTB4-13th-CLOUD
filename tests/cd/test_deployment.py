"""Offline deployment control-flow checks; no AWS mutations."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class DeploymentTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.work = Path(self.tmp.name)
        self.env = dict(os.environ, AWS_REGION="ap-northeast-2",
                        GITHUB_STEP_SUMMARY=str(self.work / "summary"))

    def orchestration(self, fail):
        shutil.copy(ROOT / "scripts/deploy_prod_services.sh", self.work)
        stub = self.work / "deploy_ecs_service_prod.sh"
        stub.write_text('\n'.join([
            '#!/usr/bin/env bash',
            'echo "$1 started" >> "$EVENTS"',
            'sleep 0.1',
            'echo "$1 finished" >> "$EVENTS"',
            'echo "| $1 | test | 0s | sha |" >> "$GITHUB_STEP_SUMMARY"',
            'if [ "$1" = "$FAIL_SERVICE" ]; then exit 1; fi',
        ]))
        self.env.update(EVENTS=str(self.work / "events"), FAIL_SERVICE=fail)
        result = subprocess.run(["bash", str(self.work / "deploy_prod_services.sh"),
                                 "image", "abcdef0", "image", "abcdef0"],
                                env=self.env, capture_output=True, text=True)
        return result, (self.work / "events").read_text().splitlines()

    def test_parallel_waits_for_both_after_failure(self):
        result, events = self.orchestration("ai")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("backend finished", events)
        self.assertIn("ai finished", events)
        self.assertIn("backend", (self.work / "summary").read_text())

    def test_backend_failure_is_not_hidden_by_ai_success(self):
        result, events = self.orchestration("backend")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ai finished", events)
        self.assertIn("backend finished", events)

    def test_parallel_success(self):
        result, events = self.orchestration("none")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(events), 4)

    def ecs(self, stable):
        digest = "sha256:" + "a" * 64
        image = "522688057030.dkr.ecr.ap-northeast-2.amazonaws.com/bookjeok-ai@" + digest
        task = "arn:aws:ecs:ap-northeast-2:522688057030:task-definition/prod-ai-task:13"
        service = {"failures": [], "services": [{
            "status": "ACTIVE", "taskDefinition": task,
            "deploymentConfiguration": {"deploymentCircuitBreaker": {
                "enable": True, "rollback": True}, "minimumHealthyPercent": 100,
                "maximumPercent": 200},
            "deployments": [{"status": "PRIMARY", "rolloutState": "COMPLETED",
                             "taskDefinition": task}],
            "pendingCount": 0 if stable else 1, "runningCount": 2, "desiredCount": 2}]}
        definition = {"taskDefinition": {"family": "prod-ai-task", "containerDefinitions": [
            {"name": "ai", "image": image}]}, "tags": []}
        (self.work / "service.json").write_text(json.dumps(service))
        (self.work / "task.json").write_text(json.dumps(definition))
        aws = self.work / "aws"
        aws.write_text('#!/bin/bash\ncase "$2" in\n'
                       'describe-services) cat "$FIXTURES/service.json";;\n'
                       'describe-task-definition) cat "$FIXTURES/task.json";;\n'
                       '*) echo "Unexpected mutation" >&2; exit 99;;\nesac\n')
        aws.chmod(0o755)
        self.env.update(PATH=str(self.work) + os.pathsep + os.environ["PATH"],
                        FIXTURES=str(self.work))
        return subprocess.run(["bash", str(ROOT / "scripts/deploy_ecs_service_prod.sh"),
                               "ai", image, "abcdef0"], env=self.env,
                              capture_output=True, text=True)

    def test_same_digest_skips_without_aws_mutation(self):
        result = self.ecs(True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("unchanged", (self.work / "summary").read_text())

    def test_unstable_service_cannot_skip(self):
        result = self.ecs(False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("failed", (self.work / "summary").read_text())


class DevDeploymentTests(unittest.TestCase):
    setUp = DeploymentTests.setUp
    test_same_digest_skips_without_aws_mutation = DeploymentTests.test_same_digest_skips_without_aws_mutation
    test_unstable_service_cannot_skip = DeploymentTests.test_unstable_service_cannot_skip

    def ecs(self, stable):
        digest = "sha256:" + "a" * 64
        image = "522688057030.dkr.ecr.ap-northeast-2.amazonaws.com/bookjeok-ai@" + digest
        task = "arn:aws:ecs:ap-northeast-2:522688057030:task-definition/dev-ai-task:40"
        service = {"failures": [], "services": [{
            "status": "ACTIVE", "taskDefinition": task,
            "deployments": [{"status": "PRIMARY", "rolloutState": "COMPLETED",
                             "taskDefinition": task}],
            "pendingCount": 0 if stable else 1, "runningCount": 1, "desiredCount": 1}]}
        definition = {"family": "dev-ai-task", "containerDefinitions": [
            {"name": "ai", "image": image}]}
        (self.work / "service.json").write_text(json.dumps(service))
        (self.work / "task.json").write_text(json.dumps(definition))
        aws = self.work / "aws"
        aws.write_text('#!/bin/bash\ncase "$2" in\n'
                       'describe-images) echo "sha256:' + 'a' * 64 + '";;\n'
                       'describe-services) cat "$FIXTURES/service.json";;\n'
                       'describe-task-definition) cat "$FIXTURES/task.json";;\n'
                       '*) echo "Unexpected mutation" >&2; exit 99;;\nesac\n')
        aws.chmod(0o755)
        self.env.update(PATH=str(self.work) + os.pathsep + os.environ["PATH"],
                        FIXTURES=str(self.work),
                        ECR_REGISTRY="522688057030.dkr.ecr.ap-northeast-2.amazonaws.com")
        return subprocess.run(["bash", str(ROOT / "scripts/deploy_ecs_service_dev.sh"),
                               "ai", "a" * 40], env=self.env,
                              capture_output=True, text=True)


if __name__ == "__main__":
    unittest.main()
