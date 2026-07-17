#!/usr/bin/env bash
# Host test wrapper (rbenv + shared infra env). Usage:
#   .superpowers/bin/host-test.sh rspec spec/...        # bundle exec rspec
#   .superpowers/bin/host-test.sh rails db:migrate      # bundle exec rails ...
#   .superpowers/bin/host-test.sh rubocop <files>
set -euo pipefail
cd /home/wital/chatwit/.claude/worktrees/captain-payment-phase2
eval "$(rbenv init -)"
export RAILS_ENV=test NODE_ENV=test \
  POSTGRES_HOST=127.0.0.1 POSTGRES_PORT=5432 \
  POSTGRES_USERNAME=postgres POSTGRES_PASSWORD=postgres \
  REDIS_URL=redis://127.0.0.1:6379/9 ENABLE_ACCOUNT_SEEDING=false
exec bundle exec "$@"
