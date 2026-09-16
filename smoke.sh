#!/usr/bin/env bash
# Prove the cross-service join happened: products from catalog, each with a
# cta from personalization, in ONE response from the gateway.
set -euo pipefail

QUERY='query { products { id name cta(segment: VIP) { variantKey headline } } }'
body=$(curl -sf --max-time 10 http://localhost:4000/graphql -H 'Content-Type: application/json' \
  -d "$(python3 -c 'import json,sys; print(json.dumps({"query": sys.argv[1]}))' "$QUERY")") \
  || { echo "gateway not reachable on 4000 — run ./dev.sh first"; exit 1; }

python3 - "$body" <<'EOF'
import json, sys
r = json.loads(sys.argv[1])
data, errors = r.get("data"), r.get("errors") or []
if errors and not data:
    # A field the supergraph lacks is a validation error, so the gateway sends
    # no data at all. Name the issue that adds the missing field.
    messages = " ".join(e.get("message", "") for e in errors)
    if 'Cannot query field "products"' in messages:
        print("FAIL — no `products` in the supergraph. With the placeholder schemas this is EXPECTED until issue #8 lands."); sys.exit(1)
    if 'Cannot query field "cta"' in messages:
        print("FAIL — no `cta` on Product in the supergraph: the join cannot happen. Expected until issue #10 lands."); sys.exit(1)
    print("FAIL — gateway returned errors and no data:")
    print(json.dumps(errors, indent=2)); sys.exit(1)
products = (data or {}).get("products")
if products is not None:
    with_cta = [p for p in products if p and p.get("cta")]
    print(f"products: {len(products)}   with a cta: {len(with_cta)}")
if errors:
    # Data AND errors: the gateway answered what it could. Typically a subgraph
    # is down, so every field it owns came back null.
    print("FAIL — the gateway returned data AND errors: the join partly failed (is a subgraph down?):")
    print(json.dumps(errors, indent=2)); sys.exit(1)
if products is None:        print("FAIL — the response has no `products`."); sys.exit(1)
if not products:            print("FAIL — zero products"); sys.exit(1)
if not with_cta:            print("FAIL — no product carried a cta: the join did not happen. Expected until issue #10 lands."); sys.exit(1)
print("OK — the federated join works")
EOF
