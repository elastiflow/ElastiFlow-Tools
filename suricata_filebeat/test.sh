#!/bin/bash



curl -X GET "http://localhost:9200/filebeat-*/_search" -u username:password -H 'Content-Type: application/json' -d'
{
  "query": {
    "match_phrase": {
      "rule.name": "GPL ATTACK_RESPONSE id check returned root"
    }
  },
  "size": 10
}' | jq 'if .hits.total.value == 10 then "\u001b[32mfound\u001b[0m" else "\u001b[31mnot found\u001b[0m" end'

