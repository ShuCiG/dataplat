# 1. Record architecture decisions

Date: 2026-11-13. Status: accepted.

## Context

The platform spans several services, and many choices trade cost against rigor. Without a record,
a later reader cannot tell a deliberate shortcut from an oversight.

## Decision

Decisions that are hard to reverse, or that knowingly deviate from what a production setup would
do, get a short record in this directory: context, decision, consequences. Records are numbered
and never rewritten; a changed decision gets a new record that supersedes the old one.

`docs/architecture.md` describes the current state and links here for the reasons.
