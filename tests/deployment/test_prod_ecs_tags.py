"""Verify empty task-definition tags are omitted from ECS registration."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/deploy_ecs_service_prod.sh"
OLD = "arn:aws:ecs:ap-northeast-2:522688057030:task-definition/prod-ai-task:10"
NEW = "arn:aws:ecs:ap-northeast-2:522688057030:task-definition/prod-ai-task:11"


def service(task_definition):
    return {
        "failures": [],
        "services": [
            {
                "serviceName": "prod-ai-service",
                "status": "ACTIVE",
                "taskDefinition": task_definition,
                "desiredCount": 1,
                "runningCount": 1,
                "pendingCount": 0,
                "deploymentConfiguration": {
                    "deploymentCircuitBreaker": {"enable": True, "rollback": True},
                    "minimumHealthyPercent": 100,
                    "maximumPercent": 200,
                },
                "deployments": [
                    {
                        "status": "PRIMARY",
                        "rolloutState": "COMPLETED",
                        "taskDefinition": task_definition,
                    }
                ],
                "events": [],
            }
        ],
    }


class ProductionTagRegistrationTest(unittest.TestCase):
    def deploy(self, tags):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "tags.json").write_text(json.dumps(tags))
            (root / "responses.json").write_text(json.dumps([service(OLD), service(NEW)]))
            mock_aws = """#!/usr/bin/env python3
import json, os, pathlib, sys
root = pathlib.Path(os.environ['FAKE_AWS_DIR'])
args = sys.argv[1:]
if args[:2] == ['ecs', 'describe-services']:
    counter = root / 'counter'
    n = int(counter.read_text()) if counter.exists() else 0
    responses = json.loads((root / 'responses.json').read_text())
    print(json.dumps(responses[min(n, 1)]))
    counter.write_text(str(n + 1))
elif args[:2] == ['ecs', 'describe-task-definition']:
    print(json.dumps({'taskDefinition': {
        'family': 'prod-ai-task',
        'containerDefinitions': [{'name': 'ai', 'image': 'old'}],
        'cpu': '1024', 'memory': '2048'
    }, 'tags': json.loads((root / 'tags.json').read_text())}))
elif args[:2] == ['ecs', 'register-task-definition']:
    (root / 'register_args.json').write_text(json.dumps(args))
    print(json.dumps({'taskDefinition': {'taskDefinitionArn': '__NEW_ARN__'}}))
elif args[:2] == ['ecs', 'update-service']:
    print('{}')
else:
    sys.exit('Unexpected AWS call: ' + str(args))
""".replace("__NEW_ARN__", NEW)
            (root / "aws").write_text(mock_aws)
            (root / "aws").chmod(0o755)
            env = dict(
                os.environ,
                PATH=f"{root}:" + os.environ["PATH"],
                FAKE_AWS_DIR=str(root),
                AWS_REGION="ap-northeast-2",
            )
            image = (
                "522688057030.dkr.ecr.ap-northeast-2.amazonaws.com/"
                "bookjeok-ai@sha256:" + "a" * 64
            )
            result = subprocess.run(
                ["bash", str(SCRIPT), "ai", image, "b" * 40],
                env=env,
                text=True,
                capture_output=True,
                timeout=10,
            )
            args_path = root / "register_args.json"
            register_args = json.loads(args_path.read_text()) if args_path.exists() else []
            return result, register_args

    def test_empty_tags_are_omitted(self):
        result, args = self.deploy([])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("--tags", args)

    def test_existing_tags_are_preserved(self):
        tags = [{"key": "team", "value": "cloud"}]
        result, args = self.deploy(tags)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--tags", args)
        self.assertEqual(json.loads(args[args.index("--tags") + 1]), tags)


if __name__ == "__main__":
    unittest.main()
