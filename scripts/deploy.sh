#!/usr/bin/env bash
set -euo pipefail

if ! docker ps --format '{{.Names}}' | grep -q '^nginx$'; then
  echo "NGINX container is not running. Start docker compose first."
  exit 1
fi

ACTIVE=""
if grep -q 'set \$backend blue:5000;' nginx/default.conf; then
  ACTIVE="blue"
elif grep -q 'set \$backend green:5000;' nginx/default.conf; then
  ACTIVE="green"
fi

if [[ -z "$ACTIVE" ]]; then
  echo "Unable to determine the current active environment from nginx/default.conf."
  exit 1
fi

if [[ "$ACTIVE" == "blue" ]]; then
  CANDIDATE="green"
  HOST_PORT="5002"
else
  CANDIDATE="blue"
  HOST_PORT="5001"
fi

echo "Current active version: $ACTIVE"
echo "Candidate version: $CANDIDATE"

docker build -t blue-green-app:v1 .

docker rm -f "$CANDIDATE" >/dev/null 2>&1 || true

docker run -d \
  --name "$CANDIDATE" \
  -p "${HOST_PORT}:5000" \
  -e APP_VERSION="${CANDIDATE}-v2" \
  -e APP_HEALTHY="true" \
  blue-green-app:v1

HEALTH_URL="http://localhost:${HOST_PORT}/health"
for _ in $(seq 1 20); do
  if curl -fsS "$HEALTH_URL" >/tmp/blue-green-health.json 2>/dev/null; then
    break
  fi
  sleep 2
done

if ! curl -fsS "$HEALTH_URL" >/tmp/blue-green-health.json 2>/dev/null; then
  echo "Health check failed for $CANDIDATE. Keeping $ACTIVE active."
  docker rm -f "$CANDIDATE" >/dev/null 2>&1 || true
  exit 1
fi

if ! python -c "import json,sys; d=json.load(open('/tmp/blue-green-health.json')); sys.exit(0 if d.get('status') == 'healthy' else 1)"; then
  echo "Candidate is not healthy. Keeping $ACTIVE active."
  docker rm -f "$CANDIDATE" >/dev/null 2>&1 || true
  exit 1
fi

cat > nginx/default.conf <<EOF
resolver 127.0.0.11 valid=5s ipv6=off;

server {
    listen 80;
    server_name localhost;

    set \$backend ${CANDIDATE}:5000;

    location / {
        proxy_pass http://\$backend;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

docker exec nginx nginx -t

docker exec nginx nginx -s reload

echo "Health check passed. Switched traffic from $ACTIVE to $CANDIDATE."
