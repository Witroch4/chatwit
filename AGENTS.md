# Chatwoot Development Guidelines (Instagram Rich Cards)

> Este documento consolida o que funcionou no projeto, lições aprendidas e checklists para evitar regressões.

---

## Build / Test / Lint

- **Setup**: `bundle install && pnpm install`
- **Run Dev**: `pnpm dev` ou `overmind start -f ./Procfile.dev`
- **Lint JS/Vue**: `pnpm eslint` / `pnpm eslint:fix`
- **Lint Ruby**: `bundle exec rubocop -a`
- **Test JS**: `pnpm test` / `pnpm test:watch`
- **Test Ruby**: `bundle exec rspec spec/path/to/file_spec.rb`
- **Single Test**: `bundle exec rspec spec/path/to/file_spec.rb:LINE_NUMBER`
- **Run Project**: `overmind start -f Procfile.dev`

## Code Style

- **Ruby**: RuboCop (largura de linha máx. \~150)
- **Vue/JS**: ESLint (Airbnb + Vue 3)
- **Componentes Vue**: PascalCase
- **Eventos**: camelCase
- **i18n**: Sem strings “nuas” em templates; use i18n
- **Erros**: Use exceções customizadas (`lib/custom_exceptions/`)
- **Models**: Valide presença/unicidade + índices corretos
- **Type Safety**: Props no Vue, strong params no Rails
- **Nomeação**: clara e consistente
- **Vue 3**: Sempre Composition API com `<script setup>` no topo

## Styling

- **Tailwind only**

  - Não escrever CSS custom
  - Não usar `scoped`
  - Não usar inline styles (salvo correções pontuais acessíveis)
  - Utilizar utilitários Tailwind e tokens de cor do `tailwind.config.js`

## Princípios Gerais

- MVP: menor dif. de código, foco no happy-path
- Sem defensivismo desnecessário
- Divida tarefas grandes em unidades pequenas e testáveis
- Itere após validação
- Não escrever specs salvo pedido explícito
- Remova código morto/não usado
- Não manter duas abordagens para a mesma lógica—escolha e implemente
- Não referenciar outros AIs em commits

---

## Fluxo **Instagram Rich Message** (Backend)

### Peças principais

- **Processor**: `Integrations::Socialwise::InstagramResponseProcessor`

  - Valida payload (`GENERIC_TEMPLATE`, `BUTTON_TEMPLATE`, `QUICK_REPLIES`)
  - Constrói payload compatível com **Instagram API** (v22.0)
  - **Cria a mensagem já em formato rico** quando _feature flag_ ativa
  - Chama `Instagram::RichMessageService` para enviar ao IG e espelhar no dashboard quando necessário

- **Service**: `Instagram::RichMessageService`

  - Valida canal, prepara `rich_message_params`
  - `send_message` → POST ao endpoint IG
  - **Mirror para dashboard** apenas se a mensagem **não** foi criada diretamente como rica
  - Logs extensivos + métricas de tempo

### Antiflicker (sem “flash” de texto)

- **Regra de ouro**: se a feature `SOCIALWISE_RICH_DASHBOARD` estiver **ativada no Account**, **crie a mensagem diretamente com** `content_type: "cards"` (ou `input_select`) e `content_attributes` mapeados.
- No service, **antes de espelhar**, checar `message_already_rich?` e **pular mirroring** se já estiver rica.
- Usar `additional_attributes: { skip_send_reply: true }` para ligar os pontos com o fluxo assíncrono sem emitir eventos em duplicidade.
- Registrar logs como: _“Message already created as rich cards, skipping mirroring”_ para confirmar o caminho correto.

### Validações de payload (resumo útil)

- **GENERIC_TEMPLATE**

  - `elements`: 1..10
  - `title` obrigatório (≤ 80 chars), `subtitle` ≤ 80
  - Máx. 3 botões por element

- **BUTTON_TEMPLATE**

  - `text` obrigatório (≤ 2000 chars)
  - 1..3 botões

- **QUICK_REPLIES**

  - `text` obrigatório (≤ 1000 chars)
  - 1..13 opções; `title` ≤ 20; `payload` ≤ 1000

- **Buttons**

  - `postback`: `payload` obrigatório
  - `web_url`: `url` http/https válida (≤ 2000 chars)

### Mapeamento para Chatwoot (renderer)

- Use `Messages::InstagramRendererMapper.map(instagram_payload)` para obter:

  - `content_type`
  - `content_attributes`
  - `fallback_text`

### Observabilidade

- Logs com prefixo (`[SOCIALWISE-INSTAGRAM-…]`) para cada etapa
- Métricas simples de duração para API do IG e para processamento

---

## Frontend (Vue 3 + Vite) — Bubbles **RichCards** e **QuickReplies**

### Diretrizes de componentização

- Local: `app/javascript/dashboard/components-next/message/bubbles/`
- **RichCards.vue**

  - Lê `contentAttributes.items`
  - Renderiza card com: `image`, `title`, `description`, `actions (link|postback)`
  - Acessibilidade: `role="group"`, `aria-label` por card
  - Evite XSS: escape de textos ao compor `alt`/innerText quando necessário
  - Métricas: `trackMetric('cw_rich_cards_render_total', …)`
  - Erros: `onErrorCaptured` + emitir `RICH_CARDS_FALLBACK`
  - **Importante:** **não** usar `import.meta` dentro de **expressões de template** (causa erro de parse do compiler); use em código JS no `<script setup>` ou encapsule em métodos/computed e chame via eventos.
  - Imagem: reservar espaço para evitar layout shift (`class="w-full h-48 object-cover"`), `loading="lazy"`, `decoding="async"` e `@error` para esconder imagem quebrada.

- **QuickReplies.vue**

  - Lê `contentAttributes.items`
  - Emite `BUS_EVENTS.RICH_POSTBACK` com `{ messageId, payload, text, type: 'quick_reply' }`
  - Métricas análogas (`cw_quick_replies_render_total`)
  - Acessibilidade: `role="button"`, foco, `:aria-label`

### Feature flag no FE

- **IMPORTANTE**: **NÃO** verificar feature flag dentro de componentes ricos (RichCards/QuickReplies). Se o componente foi chamado, significa que o backend já verificou que o flag está habilitado.
- **Arquitetura correta**:
  - Backend verifica `account.feature_enabled?('SOCIALWISE_RICH_DASHBOARD')` → cria mensagem como `content_type: "cards"`
  - Frontend vê `contentType === "cards"` → chama RichCards
  - RichCards renderiza diretamente (sem verificar flag novamente)
- **Para outros componentes** que precisam verificar flags: usar `useMapGetter('accounts/isFeatureEnabledonAccount')`:

  ```vue
  <script setup>
  import { useMapGetter } from 'dashboard/composables/store.js';

  const isFeatureEnabledOnAccount = useMapGetter(
    'accounts/isFeatureEnabledonAccount'
  );
  const currentAccountId = useMapGetter('getCurrentAccountId');

  const isRichDashboardEnabled = computed(() => {
    if (!currentAccountId.value || !isFeatureEnabledOnAccount.value) {
      return false;
    }
    return isFeatureEnabledOnAccount.value(
      currentAccountId.value,
      'SOCIALWISE_RICH_DASHBOARD'
    );
  });
  </script>
  ```

- **Evitar**: `window.globalConfig` para feature flags (pode não estar sincronizado com account-specific flags).

### Bus/Eventos

- Usar `emitter.emit(BUS_EVENTS.RICH_POSTBACK, { … })`
- Definir handlers na camada de conversa para tratar postbacks sem recarregar a UI.

### Tailwind

- Somente utilitários; sem `scoped`/CSS manual
- Classes úteis em cards: container com `max-w-sm`, títulos/descrições com `line-clamp-[2|3]` (webkit), botões com `rounded-md`, `transition-colors`, etc.

---

## Build de Frontend (Vite) — Armadilhas & Fixes

- **`::v-deep` deprecado** → usar `:deep(<selector>)`.
- **Dart Sass**: evitar **legacy JS API**; mantenha as versões atualizadas (ou aceite warnings por enquanto).
- **Funções de cor Sass**: `darken()` deprecado → use `color.scale($color, $lightness: -X%)` ou `color.adjust()`.
- **CRÍTICO - Erro**: `import.meta may appear only with 'sourceType: "module"'` → causado por usar `import.meta` **dentro do template** (ex.: handlers inline como `@load="() => import.meta.env.MODE !== 'production' && console.log(...)"`).

  **Solução completa**:

  ```vue
  <script setup>
  // ✅ Defina uma vez no script
  const isDev = import.meta.env.MODE !== 'production';

  // ✅ Crie métodos que usam a constante
  const handleImageLoad = src => {
    if (isDev) {
      console.log('[RichCards] Image loaded successfully:', src);
    }
  };
  </script>

  <template>
    <!-- ✅ Use o método no template -->
    <img @load="handleImageLoad(item.media_url || item.mediaUrl)" />
  </template>
  ```

- **Performance**: Avaliar `import.meta.env.MODE` uma vez é mais eficiente que múltiplas avaliações inline.

---

## Docker / Assets Precompile (Rails)

- Ao rodar `rake assets:precompile` em **RAILS_ENV=production**, todas as gems requeridas precisam estar instaladas no container.
- **Erro comum**: `Bundler::GemNotFound: Could not find gem 'stackprof'`

  - Garanta que `Gemfile` tenha `stackprof` em um grupo compatível com o ambiente do build (se só dev/test, o build de produção não deve exigir).
  - Execute `bundle lock` e **commit** do `Gemfile.lock`.

- **Windows vs Linux**: gems com **native extensions** (ex.: `io-console`, `stackprof`) podem falhar no Windows (MSYS2/devkit). Priorize build em Linux (Docker) e, no Windows, instale Ruby+Devkit adequados.

---

## Checklists Antiflicker

1. **Feature flag** `SOCIALWISE_RICH_DASHBOARD` **ativada** no Account.
2. **Processor** cria a mensagem **diretamente** como `content_type: 'cards'`/`input_select` com `content_attributes` completos.
3. **Service** verifica `message_already_rich?` e **pula** `mirror_rich_payload_to_dashboard` quando já for rico.
4. UI (RichCards/QuickReplies) condiciona a renderização à presença de `items` + flag no `globalConfig` quando aplicável.
5. Imagem com altura fixa para evitar _layout shift_; `@error` esconde imagem quebrada.
6. Logs esperados:

   - Backend: _“Message already created as rich cards, skipping mirroring”_
   - Frontend: `render_success`, `Image loaded successfully`.

---

## Boas Práticas de Observabilidade

- **Rails.logger** com prefixos consistentes e IDs (message_id, conversation_id)
- Métricas de tempo (ms) para chamadas IG e processamento
- No FE, `console.log` **somente** em `NODE_ENV !== 'production'`/`import.meta.env.MODE !== 'production'`
- Eventos de analytics (`trackMetric`) sem PII

---

## Snippets úteis

**Handler de postback (FE):**

```js
const handlePostback = action => {
  emitter.emit(BUS_EVENTS.RICH_POSTBACK, {
    messageId: id.value,
    payload: action.payload,
    text: action.text,
    timestamp: new Date().toISOString(),
  });
};
```

**Proteger logs dev-only (FE):**

```js
function devLog(...args) {
  if (import.meta.env.MODE !== 'production') {
    // eslint-disable-next-line no-console
    console.log(...args);
  }
}
```

**Checagem de flag (FE) - ATUALIZADO:**

```js
// ✅ Para componentes que precisam verificar flags (NÃO RichCards)
import { useMapGetter } from 'dashboard/composables/store.js';

const isFeatureEnabledOnAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);
const currentAccountId = useMapGetter('getCurrentAccountId');

const isRichDashboardEnabled = computed(() => {
  if (!currentAccountId.value || !isFeatureEnabledOnAccount.value) {
    return false;
  }
  return isFeatureEnabledOnAccount.value(
    currentAccountId.value,
    'SOCIALWISE_RICH_DASHBOARD'
  );
});

// ❌ EVITAR: window.globalConfig para feature flags account-specific
```

**Criação direta da mensagem rica (BE):**

```rb
message = conversation.messages.create!(
  content: mapped.fallback_text,
  content_type: mapped.content_type, # "cards" | "input_select"
  content_attributes: mapped.content_attributes,
  message_type: :outgoing,
  account_id: conversation.account_id,
  inbox_id: conversation.inbox_id,
  additional_attributes: { skip_send_reply: true }
)
```

---

## Ruby — Dicas adicionais

- `pattr_initialize` para serviços com dependências explícitas
- Evitar callbacks complexos em models para não duplicar broadcasts
- `update_columns` com cuidado (bypass de callbacks) apenas quando **intencional** (ex.: mirroring)

---

## 🔧 Troubleshooting Comum

### Build Vite Falhando

- **Erro**: `import.meta may appear only with 'sourceType: "module"'`
- **Solução**: Mover `import.meta` do template para script
- **Exemplo**: Ver seção "Vite Build Fix" acima

### Flash Effect Ainda Acontecendo

1. **Verificar**: Feature flag está habilitada no super admin?
2. **Verificar**: Logs mostram "Message already created as rich cards, skipping mirroring"?
3. **Verificar**: Frontend não está fazendo verificação dupla de flag?
4. **Debug**: Adicionar logs no `create_rich_outgoing_message`

### Rich Cards Não Aparecem

1. **Backend**: Verificar se `content_type` é "cards" no banco
2. **Frontend**: Verificar se `Message.vue` está chamando `RichCards`
3. **Debug**: Logs do `onMounted` no RichCards mostram `shouldRender: true`?

### Feature Flag Não Funciona

- **Verificar**: Usar `account.feature_enabled?('SOCIALWISE_RICH_DASHBOARD')` no backend
- **Verificar**: Não usar `window.globalConfig` para flags account-specific
- **Debug**: Testar no Rails console: `Account.find(X).feature_enabled?('SOCIALWISE_RICH_DASHBOARD')`

---

## Como validar que está 100% sem flicker

- No backend, procurar por:

  - **Um único** `message.created` com `content_type: 'cards'`.
  - Log: _“Message already created as rich cards, skipping mirroring”_.

- No frontend:

  - Primeiro log do `onMounted`: `shouldRender: true`, `isEnabled: true` e `items.length > 0`.
  - Em seguida, log do `@load` da imagem confirmando carregamento, **sem** aparecer uma bolha de texto antes.

---

## 🎯 FLASH EFFECT FIX - Lições Críticas (Janeiro 2025)

### Problema Resolvido: Flash Effect Eliminado ✅

**CONTEXTO**: Mensagens apareciam como texto primeiro, depois mudavam para rich cards (flash visível).

**CAUSA RAIZ**: Dupla verificação de feature flag causava race condition:

1. Backend: `account.feature_enabled?('SOCIALWISE_RICH_DASHBOARD')` → cria como `"cards"` ✅
2. Frontend: RichCards verificava flag novamente → mostrava fallback enquanto carregava ❌
3. Flag carregava → mudava para rich cards ❌
4. **Resultado**: Flash visível texto → cards

### Solução Implementada: Single Source of Truth

**PRINCÍPIO**: Apenas backend verifica feature flag. Frontend confia na decisão.

**Backend** (`lib/integrations/socialwise/instagram_response_processor.rb`):

```ruby
def create_rich_outgoing_message(conversation, instagram_payload, original_payload)
  account = conversation.account
  rich_dashboard_enabled = account.feature_enabled?('SOCIALWISE_RICH_DASHBOARD')

  if rich_dashboard_enabled
    # ✅ Criar diretamente como rica - sem flash!
    create_rich_message_directly(conversation, instagram_payload, original_payload)
  else
    # Fallback para texto normal
    create_text_message(conversation, original_payload)
  end
end

def create_rich_message_directly(conversation, instagram_payload, original_payload)
  mapped_result = Messages::InstagramRendererMapper.map(instagram_payload)

  conversation.messages.create!(
    content: mapped_result.fallback_text,
    content_type: mapped_result.content_type,           # "cards"
    content_attributes: mapped_result.content_attributes, # Rich content
    message_type: :outgoing,
    account_id: conversation.account_id,
    inbox_id: conversation.inbox_id,
    additional_attributes: { skip_send_reply: true }
  )
end
```

**Service** (`app/services/instagram/rich_message_service.rb`):

```ruby
def mirror_rich_payload_to_dashboard
  return unless rich_dashboard_enabled?

  # ✅ Pular se mensagem já foi criada como rica
  if message_already_rich?
    Rails.logger.info "Message already created as rich cards, skipping mirroring"
    return
  end

  # Apenas para mensagens criadas como texto
  # ... resto do mirroring
end

def message_already_rich?
  rich_content_types = %w[cards input_select]
  rich_content_types.include?(message.content_type)
end
```

**Frontend** (`app/javascript/dashboard/components-next/message/bubbles/RichCards.vue`):

```vue
<script setup>
// ✅ Removido verificação de feature flag
// Se este componente foi chamado, backend já verificou
const shouldRenderRichCards = computed(() => {
  return items.value.length > 0;
});
</script>
```

### Vite Build Fix: import.meta em Templates

**ERRO**: `import.meta may appear only with 'sourceType: "module"'`
**CAUSA**: Usar `import.meta.env.MODE` diretamente em template Vue

```vue
<!-- ❌ QUEBRA O BUILD -->
<img @load="() => import.meta.env.MODE !== 'production' && console.log(...)" />

<!-- ✅ SOLUÇÃO -->
<script setup>
const isDev = import.meta.env.MODE !== 'production';

const handleImageLoad = src => {
  if (isDev) {
    console.log('[RichCards] Image loaded successfully:', src);
  }
};
</script>

<template>
  <img @load="handleImageLoad(item.media_url || item.mediaUrl)" />
</template>
```

### Feature Flags: Padrão Correto

**❌ EVITAR**: Verificação dupla de flags

```vue
<!-- Não fazer isso em RichCards -->
const isRichDashboardEnabled = computed(() => { return
isFeatureEnabledOnAccount.value(currentAccountId.value,
'SOCIALWISE_RICH_DASHBOARD'); });
```

**✅ USAR**: Para outros componentes que precisam verificar flags:

```vue
<script setup>
import { useMapGetter } from 'dashboard/composables/store.js';

const isFeatureEnabledOnAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);
const currentAccountId = useMapGetter('getCurrentAccountId');

const isRichDashboardEnabled = computed(() => {
  if (!currentAccountId.value || !isFeatureEnabledOnAccount.value) {
    return false;
  }
  return isFeatureEnabledOnAccount.value(
    currentAccountId.value,
    'SOCIALWISE_RICH_DASHBOARD'
  );
});
</script>
```

### Arquitetura Final: Sem Flash

```
✅ FLUXO CORRETO (sem flash):
1. Backend: Verifica flag → Cria como "cards" → Broadcast message.created
2. Frontend: Message.vue vê contentType="cards" → Chama RichCards
3. RichCards: Renderiza imediatamente (confia no backend)
4. Resultado: Rich cards aparecem diretamente - ZERO flash! 🎉
```

### Logs de Sucesso

**Backend**:

```
[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Creating message directly as rich cards
[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Created rich message directly with ID: 12345
[SOCIALWISE-INSTAGRAM-RICH] Message already created as rich cards, skipping mirroring
```

**Frontend**:

```
[RichCards] Component mounted: {messageId: 33687, shouldRender: true}
[RichCards] Image loaded successfully: https://...
```

---

> **Status atual:** Flash effect **ELIMINADO** ✅ — Criação direta como **cards** + renderização Vue instantânea + build Vite funcionando + feature flags nativos do Chatwoot integrados.
