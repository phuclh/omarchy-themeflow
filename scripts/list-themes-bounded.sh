#!/bin/bash

# Emit at most one byte beyond the QML service's 32 KiB acceptance limit.
# The extra byte lets the service distinguish a complete response from one
# that was truncated while keeping StdioCollector memory strictly bounded.

set -u
set -o pipefail

omarchy theme list | head -c 32769
statuses=("${PIPESTATUS[@]}")

# A producer writing more than the limit normally receives SIGPIPE once head
# exits. QML detects the extra byte and rejects the truncated list.
if (( statuses[1] != 0 )); then
  exit "${statuses[1]}"
fi
if (( statuses[0] != 0 && statuses[0] != 141 )); then
  exit "${statuses[0]}"
fi
