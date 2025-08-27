# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Starting Development Server
```bash
# Start all services with foreman (recommended)
pnpm run start:dev
# or
pnpm run dev  # Uses overmind

# Or start services individually:
bundle exec rails server -p 3000
bundle exec sidekiq -C config/sidekiq.yml
bin/vite dev
```

### Building and Assets
```bash
# Build SDK only
BUILD_MODE=library bin/vite build

# Build frontend assets
bin/vite build

# Precompile assets (includes automatic SDK build)
bundle exec rake assets:precompile
```

### Testing
```bash
# JavaScript/Vue tests
pnpm test                    # Run tests once
pnpm run test:watch          # Watch mode  
pnpm run test:coverage       # With coverage

# Ruby tests
bundle exec rspec                     # All tests
bundle exec rspec spec/models         # Specific directory
bundle exec rspec spec/models/user_spec.rb  # Single file
```

### Linting and Code Quality
```bash
# JavaScript/Vue linting
pnpm run eslint            # Check
pnpm run eslint:fix        # Fix automatically

# Ruby linting/formatting
bundle exec rubocop        # Check
bundle exec rubocop -a     # Auto-correct
pnpm run ruby:prettier     # Format Ruby code
```

### Database Operations
```bash
# Standard Rails database commands
bundle exec rails db:create
bundle exec rails db:migrate
bundle exec rails db:seed
bundle exec rails db:drop db:create db:migrate db:seed  # Full reset

# Console access
bundle exec rails console
bundle exec rails dbconsole
```

### Background Jobs
```bash
# Start Sidekiq worker
bundle exec sidekiq -C config/sidekiq.yml

# Access Sidekiq web UI (in development)
# Visit /sidekiq in browser when rails server is running
```

## Architecture Overview

### Technology Stack
- **Backend**: Ruby 3.4.4, Rails 7.1+
- **Frontend**: Vue 3, Vite, TypeScript
- **Database**: PostgreSQL with pgvector extension
- **Cache/Jobs**: Redis, Sidekiq
- **Testing**: RSpec (Ruby), Vitest (JavaScript/Vue)

### Application Structure

#### Backend (Rails API + Full-Stack)
- **Models**: Core business logic in `app/models/` with ActiveRecord
- **Controllers**: API endpoints in `app/controllers/api/` and dashboard routes
- **Services**: Business logic in `app/services/` organized by domain
- **Jobs**: Background processing in `app/jobs/` using Sidekiq
- **Channels**: WebSocket functionality via ActionCable in `app/channels/`
- **Webhooks**: External integrations in `app/controllers/webhooks/`

#### Frontend (Vue/Vite)
- **Dashboard**: Main admin interface in `app/javascript/dashboard/`
- **Widget**: Customer chat widget in `app/javascript/widget/`
- **Portal**: Public help center in `app/javascript/portal/`
- **SDK**: Embeddable chat SDK in `app/javascript/sdk/`
- **Shared**: Common components and utilities in `app/javascript/shared/`

### Key Domain Models
- **Account**: Multi-tenant organization container
- **User**: System users (agents, admins)
- **Contact**: Customer contacts
- **Conversation**: Chat sessions between contacts and agents
- **Message**: Individual messages within conversations
- **Inbox**: Communication channels (email, chat, social media)
- **Agent Bot**: Automated response systems
- **Campaign**: Proactive messaging campaigns

### Communication Channels
The platform supports multiple communication channels:
- Web Widget (`channel/web_widget.rb`)
- Email (`channel/email.rb`)
- WhatsApp (`channel/whatsapp.rb`)
- Instagram (`channel/instagram.rb`)
- Facebook (`channel/facebook_page.rb`)
- Telegram, Line, SMS, Twitter

### Feature Flags
- Managed through `AccountFeatureFlag` model
- Global features in `InstallationConfig`
- Check features using `account.feature_enabled?(:feature_name)`

### Background Processing
- Uses Sidekiq for async jobs
- Jobs organized by domain in `app/jobs/`
- Webhook processing, email sending, integrations
- Scheduled jobs via sidekiq-cron

### Authentication & Authorization
- Token-based API auth via `devise_token_auth`
- Policy-based authorization using Pundit
- Multi-tenancy through `Current.account` context

## Important Development Patterns

### Service Objects
Business logic lives in service objects under `app/services/`:
```ruby
# Example pattern
result = SomeService.new(account: account, params: params).perform
```

### Message Processing
- Incoming messages processed through channel-specific services
- Message rendering/formatting in `*_renderer_mapper.rb` services
- Rich message support for cards, buttons, etc.

### Webhook Integrations
- External webhooks in `app/controllers/webhooks/`
- Processing jobs in `app/jobs/webhooks/`
- Each channel has its own webhook handling pattern

### Frontend State Management
- Vuex store for global state management
- API client in `dashboard/api/`
- ActionCable for real-time updates

### Testing Approach
- Factory-based test data with FactoryBot
- Integration tests for webhook flows
- Feature tests for end-to-end scenarios
- Mock external services in tests

## SocialWise Integration
This codebase includes extensive SocialWise integration for enhanced WhatsApp and Instagram messaging:
- Rich message templates and cards
- Flow processing and validation
- Cache management for performance
- Instagram consistency fixes
- Feature flag management for gradual rollout

## Custom Tasks
Several custom Rake tasks are available:
```bash
bundle exec rake socialwise:setup          # SocialWise integration setup
bundle exec rake socialwise:cache:clear    # Clear SocialWise cache
bundle exec rake webhook:debug              # Debug webhook issues
bundle exec rake build                      # Custom build process
```

## Enterprise Features
The codebase supports enterprise features through the `enterprise/` directory, including:
- Advanced AI integrations (Captain)
- Premium reporting and analytics
- Advanced automation rules
- SLA management