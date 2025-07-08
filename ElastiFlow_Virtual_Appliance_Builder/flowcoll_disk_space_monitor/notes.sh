#!/bin/bash

curl -s -u elastic:elastic https://localhost:9200/_nodes/stats/fs --insecure |
jq -r '
  .nodes[] as $node |
  $node.name as $name |
  $node.fs.total as $fs |
  {
    node: $name,
    total_gb: ($fs.total_in_bytes / (1024*1024*1024)) | floor,
    used_gb: (($fs.total_in_bytes - $fs.available_in_bytes) / (1024*1024*1024)) | floor,
    usage_pct: ((($fs.total_in_bytes - $fs.available_in_bytes) / $fs.total_in_bytes) * 100) | floor
  } |
  "Node: \(.node) | Used: \(.used_gb)GB | Total: \(.total_gb)GB | Usage: \(.usage_pct)%"
'
