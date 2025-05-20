#!/usr/bin/env bash

set -e

# Evaluates a transaction on preprod using Ogmios.
evaluate_transaction() {
  local file_path="$1"
  local cborHex=$(jq -r '.cborHex' "$file_path")
  local evaluation_result=$(curl -X POST "https://preprod.koios.rest/api/v1/ogmios" \
    -H "accept: application/json" \
    -H "content-type: application/json" \
    -d '{"jsonrpc":"2.0","method":"evaluateTransaction","params":{"transaction":{"cbor":"'"$cborHex"'"}}}' \
    --progress-bar)
  echo "$evaluation_result"
}
