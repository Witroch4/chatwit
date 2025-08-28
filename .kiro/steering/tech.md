# Technology Stack

## Backend Stack
- **Ruby**: 3.4.4
- **Rails**: 7.1.x (full-stack web framework)
- **Database**: PostgreSQL with pgvector extension for AI/ML features
- **Cache/Queue**: Redis for caching and background job processing
- **Background Jobs**: Sidekiq with sidekiq-cron for scheduled tasks
- **Authentication**: Devise with JWT token authentication
- **Authorization**: Pundit for policy-based access control
- **File Storage**: Active Storage with AWS S3, Azure Blob, or Google Cloud Storage

## Frontend Stack
- **JavaScript Runtime**: Node.js 23.x
- **Package Manager**: pnpm 10.x
- **Build Tool**: Vite 5.x with vite-plugin-ruby
- **Framework**: Vue.js 3.x with Vuex for state management
- **Styling**: Tailwind CSS 3.x with custom design system
- **Testing**: Vitest for unit/integration tests
- **Linting**: ESLint with Prettier for code formatting

## Development Tools
- **Code Quality**: RuboCop for Ruby, ESLint for JavaScript
- **Testing**: RSpec for Ruby backend tests
- **Containerization**: Docker with docker-compose for development
- **Process Management**: Foreman for local development

## Common Commands

### Development Setup
```bash
# Install dependencies
bundle install
pnpm install

# Database setup
rails db:create db:migrate db:seed

# Start development server
foreman start -f Procfile.dev
# OR with docker
docker-compose up
```

### Testing
```bash
# Ruby tests
docker exec chatwit-dev-rails-1 bundle exec rspec

# JavaScript tests
pnpm test
pnpm test:watch
pnpm test:coverage
```

### Code Quality
```bash
# Ruby linting
docker exec chatwit-dev-rails-1 bundle exec rubocop
docker exec chatwit-dev-rails-1 bundle exec rubocop -a  # auto-fix

# JavaScript linting
pnpm eslint
pnpm eslint:fix
```

### Build & Deploy
```bash
# Production build
./build-desenvolvimento
./build-producao

# SDK build (separate)
BUILD_MODE=library pnpm build
```

## Key Configuration Files
- `Gemfile` - Ruby dependencies
- `package.json` - Node.js dependencies and scripts
- `vite.config.ts` - Frontend build configuration
- `docker-compose.yaml` - Container orchestration
- `.env` files - Environment-specific configuration
- `config/application.rb` - Rails application configuration

## pricipal feito:
🛠️ SOLUÇÃO IMPLEMENTADA PASSO A PASSO
PASSO 1: Adicionei o método send_interactive_payload
# app/services/whatsapp/providers/whatsapp_cloud_service.rb
def send_interactive_payload(phone_number, message, interactive_payload)
  @message = message
  response = HTTParty.post(
    "#{phone_id_path}/messages",
    headers: api_headers,
    body: {
      messaging_product: 'whatsapp',
      to: phone_number,
      interactive: interactive_payload,
      type: 'interactive'
    }.to_json
  )
  process_response(response)
end
Por que era necessário?

O código tentava chamar send_interactive_payload mas o método não existia
Isso causava erro: NoMethodError: undefined method 'send_interactive_payload'
PASSO 2: Corrigi o envio duplo com skip_send_reply: true
O problema era este fluxo:

1. Cria mensagem no dashboard (SEM skip_send_reply)
2. after_create_commit dispara SendReplyJob → PRIMEIRA MENSAGEM
3. Código chama send_interactive_payload → SEGUNDA MENSAGEM
4. RESULTADO: 2 MENSAGENS NO WHATSAPP ❌
Corrigi adicionando a flag em TODOS os lugares:

A) No whatsapp_response_processor.rb:
message = conversation.messages.create!(
  content: mapped_result.fallback_text,
  content_type: mapped_result.content_type,
  content_attributes: mapped_result.content_attributes,
  message_type: :outgoing,
  account_id: conversation.account_id,
  inbox_id: conversation.inbox_id,
  additional_attributes: { skip_send_reply: true } # ← ESTA FLAG!
)
B) No processor_service.rb:
# Mensagens interativas
outgoing_message = conversation.messages.create!(
  message_type: :outgoing,
  content: text_content,
  content_type: 'integrations',
  content_attributes: { ... },
  account_id: conversation.account_id,
  inbox_id: conversation.inbox_id,
  additional_attributes: { skip_send_reply: true } # ← ESTA FLAG!
)

# Mensagens de texto
outgoing_message = conversation.messages.create!(
  message_type: :outgoing,
  content: text_content,
  content_type: 'text',
  account_id: conversation.account_id,
  inbox_id: conversation.inbox_id,
  additional_attributes: { skip_send_reply: true } # ← ESTA FLAG!
)
PASSO 3: Como a flag skip_send_reply funciona
No app/models/message.rb já existia esta lógica:

def send_reply
  # Skip sending reply if message is marked to skip
  return if additional_attributes&.dig('skip_send_reply')
  
  # Se não tem a flag, envia normalmente
  attachments.blank? ? ::SendReplyJob.perform_later(id) : ::SendReplyJob.set(wait: 2.seconds).perform_later(id)
end
🔄 FLUXO CORRIGIDO
AGORA o fluxo é:

1. Cria mensagem no dashboard (COM skip_send_reply: true)
2. send_reply() verifica a flag e PULA o envio automático
3. Código chama send_interactive_payload → ÚNICA MENSAGEM
4. RESULTADO: 1 MENSAGEM RICA NO WHATSAPP ✅