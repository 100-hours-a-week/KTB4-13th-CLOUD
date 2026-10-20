"""Exercise the deployment script with AWS responses, without contacting AWS."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/deploy_ecs_service_dev.sh"
OLD = "arn:aws:ecs:ap-northeast-2:123:task-definition/dev-ai-task:9"
NEW = OLD[:-1] + "10"


def response(state, task=NEW, running=1, pending=0):
    return {
        "failures": [],
        "services": [
            {
                "status": "ACTIVE",
                "taskDefinition": task,
                "desiredCount": 1,
                "runningCount": running,
                "pendingCount": pending,
                "deployments": [
                    {"status": "PRIMARY", "taskDefinition": task, "rolloutState": state}
                ],
                "events": [],
            }
        ],
    }


class DeploymentWaitTest(unittest.TestCase):
    def run_deployment(self, states):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "responses.json").write_text(
                json.dumps([response("COMPLETED", OLD)] + states)
            )
            (root / "aws").write_text(
                """#!/usr/bin/env python3
import json, os, pathlib, sys
root = pathlib.Path(os.environ['FAKE_AWS_DIR'])
args = sys.argv[1:]
if args[:2] == ['ecr', 'describe-images']:
    print('sha256:' + 'a' * 64)
elif args[:2] == ['ecs', 'describe-services']:
    counter = root / 'counter'
    n = int(counter.read_text()) if counter.exists() else 0
    responses = json.loads((root / 'responses.json').read_text())
    if n >= len(responses):
        sys.exit('Unexpected extra poll')
    print(json.dumps(responses[n]))
    counter.write_text(str(n + 1))
elif args[:2] == ['ecs', 'describe-task-definition']:
    print(json.dumps({'containerDefinitions': [{'name': 'ai', 'image': 'old'}]}))
elif args[:2] == ['ecs', 'register-task-definition']:
    print('arn:aws:ecs:ap-northeast-2:123:task-definition/dev-ai-task:10')
elif args[:2] == ['ecs', 'update-service']:
    print('{}')
else:
    sys.exit('Unexpected AWS call: ' + str(args))
"""
            )
            (root / "sleep").write_text("#!/bin/sh\nexit 0\n")
            for name in ("aws", "sleep"):
                (root / name).chmod(0o755)
            env = dict(
                os.environ,
                PATH=f"{root}:" + os.environ["PATH"],
                FAKE_AWS_DIR=str(root),
                ECR_REGISTRY="example.invalid",
            )
            return subprocess.run(
                ["bash", str(SCRIPT), "ai", "b" * 40],
                env=env,
                text=True,
                capture_output=True,
                timeout=10,
            )

    def test_stable_task_counts_before_rollout_completion(self):
        result = self.run_deployment([response("IN_PROGRESS"), response("COMPLETED")])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("ECS deployment completed", result.stdout)

    def test_waits_for_healthy_task_counts(self):
        result = self.run_deployment(
            [response("COMPLETED", running=0, pending=1), response("COMPLETED")]
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_failed_rollout(self):
        result = self.run_deployment([response("FAILED")])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Requested ECS deployment failed", result.stderr)

    def test_rollback(self):
        result = self.run_deployment(
            [response("IN_PROGRESS"), response("COMPLETED", OLD)]
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("rolled back or superseded", result.stderr)

    def test_describe_failure(self):
        result = self.run_deployment(
            [{"failures": [{"reason": "MISSING"}], "services": []}]
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("MISSING", result.stderr)


if __name__ == "__main__":
    unittest.main()
