#!/bin/sh
# Points demo.deckterm.cobanov.dev at the home's public IPv4, which changes with each PPPoE session.
# /etc/deckterm-demo-ddns.env holds CF_TOKEN (DNS edit on cobanov.dev only), ZONE and NAME.
set -eu
. /etc/deckterm-demo-ddns.env
ip=$(curl -4 -fsS -m 10 https://cloudflare.com/cdn-cgi/trace | sed -n 's/^ip=//p')
[ -n "$ip" ] || exit 1
api=https://api.cloudflare.com/client/v4/zones/$ZONE/dns_records
auth="Authorization: Bearer $CF_TOKEN"
rec=$(curl -fsS -m 10 -H "$auth" "$api?type=A&name=$NAME")
id=$(echo "$rec" | jq -r '.result[0].id // empty')
[ "$(echo "$rec" | jq -r '.result[0].content // empty')" = "$ip" ] && exit 0
body=$(jq -nc --arg n "$NAME" --arg c "$ip" '{type: "A", name: $n, content: $c, ttl: 60, proxied: false, comment: "DeckTerm App Review demo server, kept current by nuc"}')
if [ -n "$id" ]; then
  curl -fsS -m 10 -X PUT -H "$auth" -H "Content-Type: application/json" "$api/$id" -d "$body" >/dev/null
else
  curl -fsS -m 10 -X POST -H "$auth" -H "Content-Type: application/json" "$api" -d "$body" >/dev/null
fi
echo "$NAME -> $ip"
