curl -X GET "http://localhost:9200/your-index-name/_search" -H 'Content-Type: application/json' -d'
{
  "query": {
    "match_phrase": {
      "rule.name": "GPL ATTACK_RESPONSE id check returned root"
    }
  },
  "size": 10
}'
