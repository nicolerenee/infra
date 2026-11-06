#!/bin/sh
set -eu

# Derive the inventory from named's configuration so new zones fail closed too.
zones=$(awk '$1 == "zone" { gsub(/"/, "", $2); print $2 }' /config/zones.conf)
[ -n "$zones" ] || exit 1
for zone in $zones; do
  # Query only this server's authoritative copy; never depend on the primary
  # or recursive forwarders to decide whether an existing copy can serve.
  response=$(dig @127.0.0.1 -p 5353 "$zone" SOA +norecurse +time=1 +tries=1 +noall +comments +answer) || exit 1
  printf '%s\n' "$response" | awk -v zone="$zone." '
    /status: NOERROR,/ { ok = 1 }
    /^;; flags:/ && /[ ;]aa[ ;]/ { authoritative = 1 }
    $1 == zone && $3 == "IN" && $4 == "SOA" && $7 ~ /^[0-9]+$/ && $7 + 0 > 0 { soa = 1 }
    END { exit !(ok && authoritative && soa) }
  ' || exit 1
done
