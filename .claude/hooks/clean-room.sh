#!/bin/sh
# PreToolUse guard for the clean-room rule in AGENTS.md: no looking up other viewers on the web.
if grep -qiE 'irfan|irfanview'; then
  echo "Blocked by the clean-room rule (AGENTS.md): don't read other viewers' websites or help. Observe the reference viewer in the VM instead (observe-reference skill)." >&2
  exit 2
fi
exit 0
