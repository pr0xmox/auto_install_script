#!/bin/bash

TOKEN="Github Private Access Token"
USER="Github username"

repos=$(curl -s -H "Authorization: token $TOKEN" \
  "https://api.github.com/user/repos?per_page=100" | jq -r '.[].name')

for repo in $repos; do
  echo "Deleting $repo ..."
  curl -s -X DELETE -H "Authorization: token $TOKEN" \
    "https://api.github.com/repos/$USER/$repo"
done

echo "All repos deleted!"
