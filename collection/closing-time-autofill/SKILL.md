---
name: closing-time-autofill
description: Compatibility alias for closing-time-cli-facts. Use when the operator invokes closing-time-autofill to delegate the whole CLI session close.
license: Apache-2.0
metadata:
  version: "3.0.0"
---

# Closing Time Autofill

Read and execute [closing-time-cli-facts](../closing-time-cli-facts/SKILL.md).
This invocation delegates the same complete CLI close. Use the current runtime
and actual agent label; do not execute a second protocol or emit a legacy event
in addition to the canonical completion event. Ordinary `closing-time` remains
the interactive operator-appraisal protocol.
