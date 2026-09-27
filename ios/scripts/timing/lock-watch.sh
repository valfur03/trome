#!/bin/sh
prev=
while :; do
  cur="$(cat /tmp/ratp-sim.lock/worktree 2>/dev/null) pid=$(cat /tmp/ratp-sim.lock/pid 2>/dev/null) size=$(cat /tmp/ratp-sim.lock/size 2>/dev/null)"
  if [ "$cur" != "$prev" ]; then echo "$(date +%H:%M:%S) $cur load $(uptime | sed 's/.*averages: //')"; prev=$cur; fi
  sleep 2
done
