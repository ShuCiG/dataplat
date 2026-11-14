"""Run the dbt task of one environment once, wait for it, print its log, return its exit code.

    python tools/verify/run_dbt_task.py dev debug
    python tools/verify/run_dbt_task.py dev build --select tag:smoke

The deploy pipeline uses it as a gate: a new task definition is only accepted when
`dbt debug` succeeds, i.e. the task can sign in to Snowflake with its AWS role and reach
every object it needs. Everything about the environment is read from the platform's published
configuration in SSM, so nothing here names a resource.
"""

from __future__ import annotations

import json
import sys
import time

import boto3

POLL_SECONDS = 10
TIMEOUT_SECONDS = 20 * 60


def load_config(ssm, project: str, environment: str) -> dict:
    name = f"/{project}/{environment}/platform/config"
    return json.loads(ssm.get_parameter(Name=name)["Parameter"]["Value"])


def start(ecs, cfg: dict, command: list[str]) -> str:
    response = ecs.run_task(
        cluster=cfg["ecs_cluster"],
        taskDefinition=cfg["dbt_task_family"],  # no revision: the latest active one
        launchType="FARGATE",
        count=1,
        networkConfiguration={
            "awsvpcConfiguration": {
                "subnets": cfg["task_subnets"],
                "securityGroups": [cfg["task_security_group"]],
                "assignPublicIp": "ENABLED",
            }
        },
        overrides={"containerOverrides": [{"name": cfg["dbt_container"], "command": command}]},
        startedBy="deploy-verify",
    )
    if response["failures"]:
        raise RuntimeError(f"could not start the task: {response['failures']}")
    return response["tasks"][0]["taskArn"]


def wait(ecs, cluster: str, task_arn: str) -> dict:
    deadline = time.monotonic() + TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        task = ecs.describe_tasks(cluster=cluster, tasks=[task_arn])["tasks"][0]
        if task["lastStatus"] == "STOPPED":
            return task
        time.sleep(POLL_SECONDS)
    ecs.stop_task(cluster=cluster, task=task_arn, reason="verification timed out")
    raise TimeoutError(f"task did not stop within {TIMEOUT_SECONDS} s")


def print_log(logs, cfg: dict, task_arn: str) -> None:
    task_id = task_arn.rsplit("/", 1)[-1]
    stream = f"{cfg['dbt_log_prefix']}/{cfg['dbt_container']}/{task_id}"
    # The agent ships logs a moment after the container stops.
    time.sleep(5)
    try:
        events = logs.get_log_events(
            logGroupName=cfg["dbt_log_group"], logStreamName=stream, startFromHead=True
        )
    except logs.exceptions.ResourceNotFoundException:
        print(f"no log stream {stream}")
        return
    for event in events["events"]:
        print(event["message"])


def exit_code(task: dict, container: str) -> int:
    for c in task["containers"]:
        if c["name"] == container:
            if "exitCode" in c:
                return c["exitCode"]
            return 1  # never ran: image pull or startup failure
    return 1


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__)
        return 2
    environment, command = argv[0], argv[1:]

    session = boto3.Session()
    ecs, logs, ssm = (session.client(s) for s in ("ecs", "logs", "ssm"))
    cfg = load_config(ssm, "dataplat", environment)

    task_arn = start(ecs, cfg, command)
    print(f"started {task_arn}", flush=True)
    task = wait(ecs, cfg["ecs_cluster"], task_arn)

    print("--- task log " + "-" * 60)
    print_log(logs, cfg, task_arn)
    print("-" * 73)

    code = exit_code(task, cfg["dbt_container"])
    if code != 0:
        print(f"dbt exited with {code}; stopped reason: {task.get('stoppedReason')}")
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
