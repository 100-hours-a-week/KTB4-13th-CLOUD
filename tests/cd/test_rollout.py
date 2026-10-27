"""Exercise changed-image rollouts against a stateful, offline AWS stand-in."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
MOCK = '''#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
op = next(v for v in args if v in ["describe-images", "describe-services", "describe-task-definition", "register-task-definition", "update-service"])
root = pathlib.Path(os.environ["FIXTURES"])
data = json.loads((root / "data").read_text())
with (root / "calls").open("a") as f: f.write(op + "\\n")
if op == "describe-images": print("sha256:" + "b" * 64)
elif op == "describe-services":
    key = "after" if (root / "updated").exists() else "before"
    value = data[key]
    if key == "after" and os.environ.get("ROLLBACK") == "true":
        counter = root / "polls"
        if counter.exists():
            value = data["before"]
        else:
            counter.touch()
            value["services"][0]["deployments"][0]["rolloutState"] = "IN_PROGRESS"
    print(json.dumps(value))
elif op == "describe-task-definition":
    task = data["task"]
    print(json.dumps(task if "--query" in args else {"taskDefinition": task, "tags": []}))
elif op == "register-task-definition":
    value = args[args.index("--cli-input-json") + 1]
    task = json.loads(pathlib.Path(value[7:]).read_text() if value.startswith("file://") else value)
    assert task["containerDefinitions"][0]["image"].endswith("sha256:" + "b" * 64)
    print(data["new"] if "--query" in args else json.dumps({"taskDefinition": {"taskDefinitionArn": data["new"]}}))
elif op == "update-service":
    (root / "updated").touch()
    print("{}")
'''


class RolloutTests(unittest.TestCase):
    def run_rollout(self, environment, outcome, desired=1, rollback=False):
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            family = f"{environment}-ai-task"
            old, new = family + ":1", family + ":2"
            def service(task, state):
                return {"failures": [], "services": [{
                    "status": "ACTIVE", "taskDefinition": task,
                    "deploymentConfiguration": {"deploymentCircuitBreaker": {
                        "enable": True, "rollback": True},
                        "minimumHealthyPercent": 100, "maximumPercent": 200},
                    "desiredCount": desired, "runningCount": desired, "pendingCount": 0,
                    "deployments": [{"status": "PRIMARY", "taskDefinition": task,
                                     "rolloutState": state}]}]}
            data = {"before": service(old, "COMPLETED"),
                    "after": service(new, outcome), "new": new,
                    "task": {"family": family, "containerDefinitions": [{
                        "name": "ai", "image": "old-image"}]}}
            (work / "data").write_text(json.dumps(data))
            (work / "aws").write_text(MOCK)
            (work / "aws").chmod(0o755)
            (work / "sleep").write_text("#!/bin/sh\nexit 0\n")
            (work / "sleep").chmod(0o755)
            registry = "522688057030.dkr.ecr.ap-northeast-2.amazonaws.com"
            env = dict(os.environ, PATH=str(work) + os.pathsep + os.environ["PATH"],
                       ROLLBACK=str(rollback).lower(), FIXTURES=str(work), AWS_REGION="ap-northeast-2",
                       ECR_REGISTRY=registry, GITHUB_STEP_SUMMARY=str(work / "summary"))
            args = ["ai", "a" * 40]
            if environment == "prod":
                args.insert(1, registry + "/bookjeok-ai@sha256:" + "b" * 64)
            result = subprocess.run(["bash", str(ROOT / "scripts" /
                                    f"deploy_ecs_service_{environment}.sh"), *args],
                                    env=env, text=True, capture_output=True, timeout=10)
            return result, (work / "summary").read_text(), (work / "calls").read_text()

    def test_changed_image_success(self):
        for environment in ["dev", "prod"]:
            with self.subTest(environment=environment):
                result, summary, calls = self.run_rollout(environment, "COMPLETED")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("deployed", summary)
                self.assertIn("update-service", calls)

    def test_failed_rollout_is_not_success(self):
        for environment in ["dev", "prod"]:
            with self.subTest(environment=environment):
                result, summary, _ = self.run_rollout(environment, "FAILED")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("failed", summary)

    def test_rollback_is_not_success(self):
        for environment in ["dev", "prod"]:
            with self.subTest(environment=environment):
                result, summary, _ = self.run_rollout(environment, "COMPLETED", rollback=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("failed", summary)

    def test_zero_tasks_cannot_pass_as_healthy(self):
        for environment in ["dev", "prod"]:
            with self.subTest(environment=environment):
                result, _, calls = self.run_rollout(environment, "COMPLETED", desired=0)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("update-service", calls)


if __name__ == "__main__":
    unittest.main()
