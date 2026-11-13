#!/bin/bash

# NOTE: This script is intended to be run in a separate terminal
# window to continuously check the response timestamped

while true; do
  timestamp=$(date '+%Y-%m-%dT%H:%M:%S.%3N%:z')

  response=$(curl -sS -w '\n%{http_code}' http://localhost:30080/ 2>/dev/null)

  status=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | sed '$d')

  jq -cn \
    --arg timestamp "$timestamp" \
    --arg status "$status" \
    --arg body "$body" \
    '{timestamp: $timestamp, http_status: $status, body: $body}'

  sleep 2
done