#!/usr/bin/env bash
# Checks whether vm-app's SSH port is reachable from this VM (break-glass runbook, case C).
TARGET="10.0.1.4"
if timeout 5 bash -c "</dev/tcp/${TARGET}/22" 2>/dev/null; then
  echo "SSH port 22 on ${TARGET}: OPEN"
else
  echo "SSH port 22 on ${TARGET}: CLOSED or filtered (no answer within 5 s)"
fi