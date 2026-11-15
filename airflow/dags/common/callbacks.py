"""Failure hook. Placeholder: log it. Connect Slack or e-mail here."""

from __future__ import annotations

import logging

log = logging.getLogger(__name__)


def notify_failure(context: dict) -> None:
    ti = context["task_instance"]
    log.error("task failed: dag=%s task=%s run=%s", ti.dag_id, ti.task_id, context.get("run_id"))
