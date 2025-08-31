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
./build-desenvolvimento.ps1 #padrão
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

## Database Migration Best Practices

### PostgreSQL JSONB Index Creation

When creating indexes on JSONB fields in PostgreSQL migrations, follow these guidelines to avoid common errors:

**❌ AVOID - Problematic patterns:**

```ruby
# This can fail if no data exists with the JSON key
add_index :table, [:field1, :field2, "(meta->>'json_key')"], name: 'index_name'

# CONCURRENTLY cannot be used inside migration transactions
execute "CREATE INDEX CONCURRENTLY ..."
```

**✅ RECOMMENDED - Safe patterns:**

```ruby
def up
  # Use direct SQL with proper conditions
  execute <<-SQL
    CREATE INDEX IF NOT EXISTS index_name
    ON table_name (field1, field2, (meta->>'json_key'))
    WHERE meta->>'json_key' IS NOT NULL;
  SQL
end

def down
  remove_index :table_name, name: 'index_name'
end
```

**Key lessons learned:**

- Always use `IF NOT EXISTS` to prevent duplicate index errors
- Add `WHERE` conditions to optimize indexes on sparse JSONB data
- Never use `CONCURRENTLY` inside migration transactions
- Test migrations on databases with and without existing data
- Use `execute` with raw SQL for complex JSONB index expressions

## Principais Soluções Implementadas:

### � EÇRRO CRÍTICO: Conversation ID vs Display ID

**PROBLEMA ENCONTRADO**: Controllers que lidam com conversas devem usar `display_id`, não `id` interno.

**❌ CÓDIGO INCORRETO:**

```ruby
# NUNCA faça isso em controllers de conversation!
conversation = current_account.conversations.find(params[:conversation_id])
```

**✅ CÓDIGO CORRETO:**

```ruby
# SEMPRE use display_id para buscar conversas em controllers
conversation = current_account.conversations.find_by!(display_id: params[:conversation_id])
```

**Por que isso acontece?**

- `params[:conversation_id]` na URL contém o `display_id` público
- `id` é o ID interno do banco de dados
- Usar `find(id)` pode retornar a conversa errada!

**Exemplo do bug corrigido:**

- URL: `/conversations/1987` (display_id)
- `find(1987)` buscava por `id = 1987` → conversa errada
- `find_by!(display_id: 1987)` busca corretamente → conversa certa

**Controllers que seguem o padrão correto:**

- `MessagesController` ✅
- `ConversationsController` ✅
- `StickersController` ✅ (corrigido)

### 🛠️ SOLUÇÃO IMPLEMENTADA PASSO A PASSO

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

### 🚀 OTIMIZAÇÃO: Evitando N+1 Queries com Active Storage

**PROBLEMA COMUM**: Consultas N+1 ao buscar attachments com URLs ou blobs.

**❌ CÓDIGO INEFICIENTE:**

```ruby
# Causa N+1 queries - uma para attachments, uma para cada blob
query.includes(:file_attachment).map do |attachment|
  { url: attachment.download_url } # Cada download_url gera nova query!
end
```

**✅ CÓDIGO OTIMIZADO:**

```ruby
# Evita N+1 queries - carrega blobs de uma vez
query.includes(file_attachment: :blob).map do |attachment|
  { url: attachment.download_url } # URLs geradas sem queries extras
end
```

**Padrão Geral para Active Storage:**

```ruby
# Para múltiplos attachments
Model.includes(attachment: :blob)

# Para múltiplos attachments com variações
Model.includes(avatar_attachment: :blob, document_attachment: :blob)

# Para has_many_attached
Model.includes(images_attachments: :blob)
```

**Resultado da otimização:**

- **Antes**: N+1 queries (1 + número de registros)
- **Depois**: 2-3 queries totais (independente da quantidade)
- **Performance**: Melhoria significativa em listagens com attachments

### 🔧 PADRÃO: URLs Públicas para Active Storage

**PROBLEMA COMUM**: URLs `/disk/` do Active Storage local não são acessíveis para serviços externos.

**CAUSA RAIZ**: `blob.url` gera URLs internas que não funcionam para APIs externas (WhatsApp, Telegram, etc.).

**❌ CÓDIGO PROBLEMÁTICO:**

```ruby
def download_url
  file.attached? ? file.blob.url : '' # Gera URLs /disk/ não públicas
end
```

**✅ CÓDIGO CORRETO:**

```ruby
def download_url
  if file.attached?
    # Use redirect URL para serviços externos
    Rails.application.routes.url_helpers.rails_blob_url(file.blob, only_path: false)
  else
    ''
  end
end
```

**Alternativas por Contexto:**

```ruby
# Para uso interno (dashboard)
file.blob.url

# Para APIs externas (WhatsApp, webhooks)
rails_blob_url(file.blob, only_path: false)

# Para downloads diretos
rails_blob_path(file.blob, disposition: "attachment")

# Para exibição inline
rails_blob_path(file.blob, disposition: "inline")
```

**Resultado:**

- ✅ URLs acessíveis externamente
- ✅ Compatibilidade com APIs de terceiros
- ✅ Melhor controle sobre disposição de arquivos

### 🔧 CORREÇÃO: Encoding de Dados Binários

**PROBLEMA**: Erro "incompatible character encodings: BINARY (ASCII-8BIT) and UTF-8".

**CAUSA RAIZ**: HTTParty retorna dados binários com encoding UTF-8, causando conflito.

**❌ CÓDIGO PROBLEMÁTICO:**

```ruby
media_data = response.body # Pode ter encoding UTF-8
temp_file.write(media_data) # Falha com dados binários
```

**✅ CÓDIGO CORRIGIDO:**

```ruby
# Force binary encoding para dados de imagem
media_data = response.body.force_encoding('BINARY')
temp_file.binmode # Garante modo binário
binary_data = media_data.force_encoding('BINARY')
temp_file.write(binary_data)
```

**Melhorias implementadas:**

- Forçar encoding BINARY em dados de imagem
- Modo binário em arquivos temporários
- Validação de assinaturas de imagem com encoding correto
- Logs detalhados para debugging de encoding

**Resultado:**

- ✅ Upload de stickers funciona sem erros de encoding
- ✅ Dados binários processados corretamente
- ✅ Compatibilidade com todos os formatos de imagem

### 🎯 PADRÃO: Sender Correto e Status Checks

**PROBLEMA COMUM**: Mensagens aparecem como enviadas pelo sistema em vez do usuário, sem status checks.

**CAUSA RAIZ**: Criação direta de mensagens sem seguir padrões nativos do MessageBuilder.

**❌ CÓDIGO PROBLEMÁTICO:**

```ruby
# Criação direta da mensagem sem MessageBuilder
message = @conversation.messages.create!(
  content: content,
  message_type: :outgoing,
  account_id: @conversation.account_id,
  inbox_id: @conversation.inbox_id
)
# Sem atualização de source_id para status checks
```

**✅ CÓDIGO CORRETO:**

```ruby
# Usa MessageBuilder nativo para sender correto
message_params = ActionController::Parameters.new({
  content: content,
  content_type: content_type,
  content_attributes: content_attributes,
  message_type: 'outgoing',
  additional_attributes: additional_attributes
})

builder = Messages::MessageBuilder.new(@user, @conversation, message_params)
message = builder.perform

# Atualiza source_id para status checks (padrão nativo)
if response[:message_id].present?
  message.update!(source_id: response[:message_id])
end
```

**Por que usar MessageBuilder:**

- ✅ **Sender correto**: Mensagens aparecem como enviadas pelo usuário
- ✅ **Content attributes**: Preserva dados estruturados para frontend
- ✅ **Additional attributes**: Suporte para flags como `skip_send_reply`
- ✅ **Status checks**: Habilita webhooks de status (✓ → ✓✓ → ✓✓ azul)
- ✅ **Compatibilidade**: Funciona com todos os recursos nativos

## 🗄️ ARQUITETURA DE CACHE DO CHATWOOT

### **Padrão Híbrido de Cache**

O Chatwoot utiliza uma arquitetura híbrida de cache com duas camadas principais:

#### **1. Redis::Alfred - Cache Customizado (Padrão Principal)**

- **Propósito**: Cache específico para funcionalidades core do sistema
- **Conexão**: Connection pool `$alfred` com namespace `alfred`
- **Localização**: `lib/redis/alfred.rb`
- **Chaves**: Definidas em `lib/redis/redis_keys.rb`

**Funcionalidades que usam Redis::Alfred:**

- Online presence (usuários e contatos)
- Round robin assignment de agentes
- Conversation emails (anti-duplicação)
- Rate limiting (Rack::Attack)
- Locks/mutexes para operações críticas
- Cache de media_id para APIs externas (WhatsApp, Telegram, etc.)
- Métricas de sistema e analytics

**Exemplo de uso:**

```ruby
# Salvar no cache
Redis::Alfred.setex(cache_key, value, 30.days)

# Recuperar do cache
cached_value = Redis::Alfred.get(cache_key)

# Verificar existência
exists = Redis::Alfred.exists?(cache_key)

# Deletar
Redis::Alfred.delete(cache_key)
```

#### **2. Rails.cache - Cache Padrão do Rails**

- **Propósito**: Fragment caching, action caching, cache geral
- **Configuração**: Varia por ambiente
- **Desenvolvimento**: `:memory_store` (quando habilitado)
- **Produção**: Cache padrão do Rails

### **Chaves Redis Padronizadas**

Todas as chaves Redis seguem um padrão definido em `lib/redis/redis_keys.rb`:

```ruby
# Exemplos de chaves do sistema
ONLINE_STATUS = 'ONLINE_STATUS::%<account_id>d'.freeze
CONVERSATION_MAILER_KEY = 'CONVERSATION::%<conversation_id>d'.freeze

# Padrão para cache de mídia externa
WHATSAPP_MEDIA_CACHE = 'WHATSAPP_MEDIA::%<channel_id>d::%<url_hash>s'.freeze
TELEGRAM_MEDIA_CACHE = 'TELEGRAM_MEDIA::%<channel_id>d::%<url_hash>s'.freeze

# Padrão para cache de recursos por conta
RESOURCE_CACHE = 'RESOURCE::%<account_id>d::%<resource_type>s'.freeze
```

### **Implementação Padrão**

**❌ EVITAR (Rails.cache):**

```ruby
Rails.cache.fetch(cache_key, expires_in: 30.days) do
  expensive_operation
end
```

**✅ PADRÃO CHATWOOT (Redis::Alfred):**

```ruby
cached_value = Redis::Alfred.get(cache_key)
if cached_value.nil?
  value = expensive_operation
  Redis::Alfred.setex(cache_key, value, 30.days)
  value
else
  cached_value
end
```

### **Configuração de Cache por Ambiente**

#### **Desenvolvimento:**

- **Redis::Alfred**: ✅ Sempre ativo
- **Rails.cache**: `:memory_store` (habilitado via `rails dev:cache`)
- **Arquivo**: `tmp/caching-dev.txt` deve existir

#### **Produção:**

- **Redis::Alfred**: ✅ Sempre ativo
- **Rails.cache**: Cache padrão do Rails
- **Configuração**: Automática

### **Boas Práticas de Cache**

1. **Use Redis::Alfred para:**

   - Cache de dados críticos do sistema
   - Operações que precisam de consistência
   - Dados compartilhados entre processos
   - Funcionalidades core do Chatwoot

2. **Use Rails.cache para:**

   - Fragment caching de views
   - Cache temporário de computações
   - Cache de dados não críticos

3. **Chaves de Cache:**

   - Sempre use as constantes de `Redis::RedisKeys`
   - Inclua account_id para isolamento
   - Use format() para interpolação segura

4. **TTL (Time To Live):**
   - Media IDs de APIs externas: 30 dias
   - Recursos customizados: 1 hora
   - Métricas e analytics: 1 hora
   - Online presence: Baseado em atividade

### **Debugging de Cache**

```ruby
# Verificar se uma chave existe
Redis::Alfred.exists?(cache_key)

# Ver valor atual
Redis::Alfred.get(cache_key)

# Limpar cache específico
Redis::Alfred.delete(cache_key)

# Para desenvolvimento, limpar tudo
Redis::Alfred.flushdb # ⚠️ Cuidado em produção!
```

**Benefícios do Padrão:**

- ✅ Consistência arquitetural com o Chatwoot
- ✅ Performance otimizada com connection pooling
- ✅ Namespace isolado (`alfred`)
- ✅ Chaves organizadas e documentadas
- ✅ Compatibilidade total com o sistema existente
- ✅ Facilita debugging e monitoramento

### 🎨 CORREÇÃO: Layout de Abas em Modais

**PROBLEMA**: Texto de abas cortado em modais pequenos.

**❌ LAYOUT PROBLEMÁTICO:**

```vue
<!-- Abas com largura fixa que cortam texto -->
<div class="flex">
  <button class="flex-1 py-3 px-4 text-sm">
    {{ tab.label }}
  </button>
</div>
```

**✅ LAYOUT RESPONSIVO:**

```vue
<!-- Abas responsivas com scroll horizontal -->
<div class="flex overflow-x-auto">
  <button class="flex-shrink-0 py-3 px-3 text-xs min-w-0">
    <span class="truncate">{{ tab.label }}</span>
  </button>
</div>
```

**Melhorias aplicadas:**

- `overflow-x-auto`: Permite scroll horizontal nas abas
- `flex-shrink-0`: Impede que abas encolham demais
- `text-xs`: Texto menor para caber melhor
- `truncate`: Corta texto longo com "..."
- `min-w-0`: Permite que flex items encolham além do conteúdo

## 🏗️ PADRÕES ARQUITETURAIS DO CHATWOOT

### **🔄 PADRÃO: Service Objects para Lógica de Negócio**

**REGRA**: Encapsule lógica complexa em service objects organizados por domínio.

**Estrutura Padrão:**

```
app/services/
├── conversations/
├── messages/
├── integrations/
├── [channel_name]/
└── [domain]/
```

**✅ IMPLEMENTAÇÃO:**

```ruby
# app/services/messages/message_processor_service.rb
class Messages::MessageProcessorService
  def initialize(message, user = nil)
    @message = message
    @user = user
  end

  def perform
    # Lógica de negócio aqui
    Rails.logger.info "#{self.class.name}: Processing message #{@message.id}"

    result = process_message

    Rails.logger.info "#{self.class.name}: Completed processing"
    result
  end

  private

  def process_message
    # Implementação específica
  end
end
```

**Benefícios:**

- ✅ Lógica de negócio isolada dos controllers
- ✅ Fácil testabilidade
- ✅ Reutilização de código
- ✅ Logs estruturados

### **🎯 PADRÃO: Error Handling Consistente**

**REGRA**: Use tratamento de erro padronizado em todos os services.

**✅ PADRÃO RECOMENDADO:**

```ruby
class BaseService
  class ServiceError < StandardError; end
  class ValidationError < ServiceError; end
  class ExternalApiError < ServiceError; end

  def perform
    Rails.logger.info "#{self.class.name}: Starting operation"

    validate_inputs!
    result = execute_operation

    Rails.logger.info "#{self.class.name}: Operation completed successfully"
    result
  rescue ValidationError => e
    Rails.logger.error "#{self.class.name}: Validation failed: #{e.message}"
    { success: false, error: e.message, type: 'validation' }
  rescue ExternalApiError => e
    Rails.logger.error "#{self.class.name}: External API error: #{e.message}"
    { success: false, error: e.message, type: 'external_api' }
  rescue StandardError => e
    Rails.logger.error "#{self.class.name}: Unexpected error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    { success: false, error: 'Internal server error', type: 'internal' }
  end

  private

  def validate_inputs!
    # Implementar validações específicas
  end

  def execute_operation
    # Implementar lógica específica
  end
end
```

### **📋 PADRÃO: MessageBuilder para Criação de Mensagens**

**REGRA**: Sempre use `Messages::MessageBuilder` para criar mensagens, nunca criação direta.

**❌ EVITAR:**

```ruby
# Criação direta - não segue padrões nativos
message = @conversation.messages.create!(
  content: content,
  message_type: :outgoing,
  account_id: @conversation.account_id,
  inbox_id: @conversation.inbox_id
)
```

**✅ PADRÃO CORRETO:**

```ruby
# Use MessageBuilder para garantir sender correto e compatibilidade
message_params = ActionController::Parameters.new({
  content: content,
  content_type: content_type,
  content_attributes: content_attributes,
  message_type: 'outgoing', # String, não symbol
  additional_attributes: additional_attributes
})

builder = Messages::MessageBuilder.new(@user, @conversation, message_params)
message = builder.perform
```

**Por que usar MessageBuilder:**

- ✅ **Sender correto**: `message_type == 'outgoing' ? (message_sender || @user) : @conversation.contact`
- ✅ **Content attributes**: Preserva dados estruturados para frontend
- ✅ **Additional attributes**: Suporte para flags como `skip_send_reply`
- ✅ **Compatibilidade**: Funciona com todos os recursos nativos do Chatwoot

### **🔄 PADRÃO: Transformação de Chaves Backend ↔ Frontend**

**REGRA**: Backend usa snake_case, Frontend usa camelCase com transformação automática.

**Fluxo de Dados:**

```
Backend (Ruby)     →    Frontend (JavaScript)
snake_case         →    camelCase (automático)
content_attributes →    contentAttributes
custom_data        →    customData
user_preferences   →    userPreferences
```

**❌ ERRO COMUM:**

```javascript
// Frontend procurando por snake_case (não funciona)
const customData = computed(() => {
  return contentAttributes.value?.custom_data || {}; // ❌
});
```

**✅ PADRÃO CORRETO:**

```javascript
// Frontend deve usar camelCase (transformação automática)
const customData = computed(() => {
  return contentAttributes.value?.customData || {}; // ✅
});
```

**Transformação Automática:**

```javascript
// Componentes que recebem dados do backend
const processedData = computed(() => {
  return useCamelCase(props.backendData, { deep: true });
});
```

**Envio para Backend:**

```javascript
// Converter de volta para snake_case ao enviar
const payload = useSnakeCase({
  contentType: 'text',
  customData: { key: 'value' },
});
// Resultado: { content_type: 'text', custom_data: { key: 'value' } }
```

### **🚫 PADRÃO: Skip Send Reply para Evitar Envio Duplo**

**REGRA**: Use `skip_send_reply: true` quando o serviço customizado já envia a mensagem.

**Problema do Envio Duplo:**

```
1. Serviço customizado envia → WhatsApp API
2. SendReplyJob também envia → WhatsApp API (DUPLICADO!)
```

**✅ SOLUÇÃO:**

```ruby
# No serviço customizado
additional_attributes: {
  skip_send_reply: true # Previne SendReplyJob
}

# Message model verifica a flag
def send_reply
  return if additional_attributes&.dig('skip_send_reply')
  # ... resto do código de envio
end
```

### **📡 PADRÃO: Source ID para Status Checks**

**REGRA**: Sempre atualize `source_id` após envio bem-sucedido para habilitar status checks.

**✅ PADRÃO SendOnWhatsappService:**

```ruby
def send_session_message
  phone_number = message.conversation.contact_inbox.source_id
  message_id = channel.send_message(phone_number, message)
  message.update!(source_id: message_id) if message_id.present?
end
```

**Aplicação em Serviços Customizados:**

```ruby
# Após envio bem-sucedido
if response[:success] && response[:message_id].present?
  message.update!(source_id: response[:message_id])
end
```

**Resultado:**

- ✅ Webhooks de status funcionam (sent/delivered/read)
- ✅ Checks visuais aparecem (✓ → ✓✓ → ✓✓ azul)
- ✅ Compatibilidade com sistema nativo

### **🗄️ PADRÃO: Cache com Redis::Alfred**

**REGRA**: Use `Redis::Alfred` para cache, não `Rails.cache`, seguindo padrão Chatwoot.

**❌ EVITAR:**

```ruby
Rails.cache.fetch(cache_key, expires_in: 30.days) do
  # operação custosa
end
```

**✅ PADRÃO CHATWOOT:**

```ruby
# Verificar cache
cached_value = Redis::Alfred.get(cache_key)
if cached_value.nil?
  # Cache miss - executar operação
  value = expensive_operation
  Redis::Alfred.setex(cache_key, value, 30.days)
  value
else
  cached_value
end
```

**Chaves Padronizadas:**

```ruby
# lib/redis/redis_keys.rb
WHATSAPP_MEDIA_CACHE = 'WHATSAPP_MEDIA::%<channel_id>d::%<url_hash>s'.freeze

# Uso
cache_key = format(Redis::RedisKeys::WHATSAPP_MEDIA_CACHE,
                   channel_id: @channel.id,
                   url_hash: url_hash)
```

### **🎨 PADRÃO: Componentes Frontend para Mensagens**

**REGRA**: Siga a estrutura de componentes de bolha para novos tipos de mensagem.

**Estrutura Padrão:**

```
app/javascript/dashboard/components-next/message/
├── bubbles/
│   ├── Base.vue           # Componente base
│   ├── Text/              # Mensagens de texto
│   ├── Image.vue          # Imagens
│   ├── File.vue           # Arquivos
│   └── [NovoTipo].vue     # Novo tipo de mensagem
├── Message.vue            # Componente principal
└── constants.js           # Constantes (CONTENT_TYPES)
```

**Padrão de Implementação:**

```vue
<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BaseBubble from './Base.vue';
import { useMessageContext } from '../provider.js';

const { contentAttributes, message } = useMessageContext();

// Use camelCase para acessar dados transformados
const customData = computed(() => {
  return contentAttributes.value?.customData || {};
});

// Estados de loading e erro
const isLoading = ref(false);
const error = ref(null);
</script>

<template>
  <BaseBubble>
    <div v-if="error" class="error-state">
      {{ error }}
    </div>
    <div v-else-if="isLoading" class="loading-state">Loading...</div>
    <div v-else>
      <!-- Conteúdo da bolha -->
    </div>
  </BaseBubble>
</template>
```

**Registrar Novo Tipo:**

```javascript
// constants.js
export const CONTENT_TYPES = {
  TEXT: 'text',
  IMAGE: 'image',
  FILE: 'file',
  CUSTOM_TYPE: 'custom_type', // Novo tipo
};

// Message.vue
import CustomTypeBubble from './bubbles/CustomType.vue';

const componentMap = {
  [CONTENT_TYPES.CUSTOM_TYPE]: CustomTypeBubble,
};
```

### **🌐 PADRÃO: Integração com APIs Externas**

**REGRA**: Use padrão consistente para integração com APIs de terceiros.

**Estrutura Padrão:**

```
lib/integrations/[service]/
├── base_service.rb        # Configuração base
├── client.rb             # Cliente HTTP
├── processor_service.rb   # Processamento principal
└── response_processor.rb  # Processamento de respostas
```

**✅ IMPLEMENTAÇÃO BASE:**

```ruby
# lib/integrations/external_service/base_service.rb
class Integrations::ExternalService::BaseService
  include HTTParty

  base_uri ENV['EXTERNAL_SERVICE_BASE_URL']

  def initialize(channel)
    @channel = channel
    @credentials = @channel.provider_config
  end

  private

  def api_headers
    {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{@credentials['access_token']}"
    }
  end

  def handle_response(response)
    case response.code
    when 200..299
      { success: true, data: response.parsed_response }
    when 400..499
      { success: false, error: 'Client error', code: response.code }
    when 500..599
      { success: false, error: 'Server error', code: response.code }
    else
      { success: false, error: 'Unknown error', code: response.code }
    end
  end
end
```

**Retry Pattern:**

```ruby
def with_retry(max_attempts: 3, delay: 1)
  attempts = 0
  begin
    attempts += 1
    yield
  rescue StandardError => e
    if attempts < max_attempts
      Rails.logger.warn "Attempt #{attempts} failed: #{e.message}. Retrying in #{delay}s..."
      sleep(delay)
      retry
    else
      Rails.logger.error "All #{max_attempts} attempts failed: #{e.message}"
      raise
    end
  end
end
```

### **📊 PADRÃO: Logs Estruturados para Debugging**

**REGRA**: Use logs estruturados e informativos para facilitar debugging.

**✅ PADRÃO DE LOGS:**

```ruby
Rails.logger.info "#{self.class.name}: Starting operation for #{resource} #{id}"
Rails.logger.info "  - Key detail 1: #{value1}"
Rails.logger.info "  - Key detail 2: #{value2}"

# Para erros com contexto
Rails.logger.error "#{self.class.name}: Operation failed: #{error.message}"
Rails.logger.error "  - Context: #{context_info}"
Rails.logger.error "  - Backtrace: #{error.backtrace.first(5).join(', ')}"
```

**Níveis de Log por Contexto:**

```ruby
# Informações de fluxo normal
Rails.logger.info "Processing started"

# Avisos para situações não ideais
Rails.logger.warn "Fallback method used due to: #{reason}"

# Erros recuperáveis
Rails.logger.error "API call failed, retrying: #{error.message}"

# Erros críticos
Rails.logger.fatal "System failure: #{error.message}"
```

**Logs Estruturados para APIs:**

```ruby
Rails.logger.info "API Request: #{method} #{url}"
Rails.logger.info "  - Headers: #{headers.except('Authorization')}"
Rails.logger.info "  - Body: #{body.truncate(500)}"

Rails.logger.info "API Response: #{response.code}"
Rails.logger.info "  - Duration: #{duration}ms"
Rails.logger.info "  - Body: #{response.body.truncate(500)}"
```

### **🗃️ PADRÃO: Performance de Banco de Dados**

**REGRA**: Otimize consultas e use índices apropriados para performance.

**Evitar N+1 Queries:**

```ruby
# ❌ N+1 Query
users.each do |user|
  puts user.profile.name # Query para cada user
end

# ✅ Eager Loading
users.includes(:profile).each do |user|
  puts user.profile.name # Uma query apenas
end
```

**Índices para JSONB:**

```ruby
# Migration para campos JSONB
def up
  execute <<-SQL
    CREATE INDEX IF NOT EXISTS index_table_on_jsonb_field
    ON table_name USING gin (jsonb_field)
    WHERE jsonb_field IS NOT NULL;
  SQL
end

# Para consultas específicas
execute <<-SQL
  CREATE INDEX IF NOT EXISTS index_table_on_jsonb_key
  ON table_name ((jsonb_field->>'specific_key'))
  WHERE jsonb_field->>'specific_key' IS NOT NULL;
SQL
```

**Paginação Eficiente:**

```ruby
# ✅ Use cursor-based pagination para grandes datasets
def paginated_results(cursor = nil, limit = 50)
  query = base_query.limit(limit)
  query = query.where('id > ?', cursor) if cursor.present?
  query.order(:id)
end
```

**Bulk Operations:**

```ruby
# ✅ Para inserções em massa
User.insert_all(user_data, returning: %w[id email])

# ✅ Para atualizações em massa
User.where(active: false).update_all(status: 'inactive')
```

### **🔒 PADRÃO: Segurança e Validação**

**REGRA**: Sempre valide dados de entrada e sanitize outputs.

**Validações de Modelo:**

```ruby
class Message < ApplicationRecord
  validates :content, presence: true, length: { maximum: 10000 }
  validates :message_type, inclusion: { in: %w[incoming outgoing] }
  validates :account_id, presence: true

  # Sanitização automática
  before_save :sanitize_content

  private

  def sanitize_content
    self.content = ActionController::Base.helpers.sanitize(content) if content_changed?
  end
end
```

**Strong Parameters:**

```ruby
def message_params
  params.require(:message).permit(
    :content, :content_type, :message_type,
    content_attributes: {},
    additional_attributes: {}
  )
end
```

**Rate Limiting:**

```ruby
# config/application.rb
config.middleware.use Rack::Attack

# config/initializers/rack_attack.rb
Rack::Attack.throttle('api/requests', limit: 100, period: 1.hour) do |req|
  req.ip if req.path.start_with?('/api/')
end
```

## 🎯 CHECKLIST DE CONFORMIDADE COM PADRÕES CHATWOOT

### **Backend (Ruby):**

- [ ] Usa `Messages::MessageBuilder` para criar mensagens
- [ ] Usa `ActionController::Parameters.new()` para parâmetros
- [ ] Inclui `content_attributes` para dados do frontend
- [ ] Usa `additional_attributes: { skip_send_reply: true }` quando necessário
- [ ] Atualiza `source_id` após envio bem-sucedido
- [ ] Usa `Redis::Alfred` para cache com chaves padronizadas
- [ ] Logs estruturados e informativos
- [ ] Service objects para lógica de negócio
- [ ] Tratamento de erro consistente
- [ ] Validações e sanitização adequadas

### **Frontend (JavaScript/Vue):**

- [ ] Usa `useMessageContext()` para acessar dados da mensagem
- [ ] Acessa dados em camelCase (transformação automática)
- [ ] Estende `BaseBubble` para novos tipos de bolha
- [ ] Segue estrutura de componentes estabelecida
- [ ] Trata estados de loading e erro adequadamente
- [ ] Usa composables para lógica reutilizável

### **Performance & Segurança:**

- [ ] Evita N+1 queries com eager loading
- [ ] Usa índices apropriados para consultas
- [ ] Implementa paginação eficiente
- [ ] Rate limiting para APIs públicas
- [ ] Validação e sanitização de dados
- [ ] Logs não expõem informações sensíveis

### **Integração:**

- [ ] Content type definido em `CONTENT_TYPES` (constants.js)
- [ ] Enum correspondente no backend (`Message` model)
- [ ] Componente registrado no `Message.vue`
- [ ] Testes unitários implementados
- [ ] Documentação atualizada
- [ ] Padrão de retry para APIs externas

**Seguindo estes padrões, qualquer nova funcionalidade será totalmente compatível com a arquitetura nativa do Chatwoot!** 🎯
