#!/usr/bin/env bash
# Docker-network RSpec runner for the captain-payment-phase2 Chatwit worktree.
# Fallback while Docker Desktop host port forwarding is broken: runs specs
# inside the chatwit:development image on minha_rede, reaching the shared
# postgres/redis by service name. Never loads .env (docker run ignores env_file).
#
# Usage:
#   .superpowers/bin/rspec-docker.sh spec/path/file_spec.rb[:LINE] [...]
#   RUNNER_CMD="bundle exec rails db:migrate" .superpowers/bin/rspec-docker.sh
set -euo pipefail

WORKTREE=/home/wital/chatwit/.claude/worktrees/captain-payment-phase2
CMD=${RUNNER_CMD:-"bundle exec rspec"}

exec docker run --rm \
  --cpus 6 --memory 6g \
  --network minha_rede \
  -v "$WORKTREE:/app" \
  -v chatwit_wt_phase2_gems:/gems \
  -v chatwit_node_modules:/app/node_modules \
  -e RAILS_ENV=test \
  -e NODE_ENV=test \
  -e POSTGRES_HOST=postgres \
  -e POSTGRES_PORT=5432 \
  -e POSTGRES_USERNAME=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e REDIS_URL=redis://redis:6379/9 \
  -e ENABLE_ACCOUNT_SEEDING=false \
  -w /app \
  chatwit:development \
  sh -c "$CMD \"\$@\"" -- "$@"
