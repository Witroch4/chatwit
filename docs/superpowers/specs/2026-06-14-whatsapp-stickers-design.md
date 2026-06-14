# Figurinhas (WhatsApp Stickers) — Design

> **Data:** 2026-06-14
> **Status:** Aprovado (defaults confirmados)
> **Escopo:** Etapa 3 da migração SocialWise → Chatwit (CLAUDE.md). Rebuild enxuto do recurso de figurinhas que existia no fork legado v4.4, **sem** Giphy/API externa.
> **Base atual:** Chatwit 4.13.0 (Chatwoot 4.13)

---

## 1. Objetivo

Permitir que agentes **criem/salvem** figurinhas (a partir de imagens, da câmera, ou de figurinhas recebidas na conversa) e **enviem** figurinhas nativas do WhatsApp, com um botão de figurinha no input — **igual no desktop e no PWA mobile**.

Referência visual: botão de figurinha do WhatsApp dentro do input (imagens enviadas pelo usuário).

## 2. Escopo

**Dentro do escopo (MVP):**
- Biblioteca de figurinhas **por conta** (compartilhada entre agentes).
- "Recentes" **por usuário** (em `user.ui_settings['recent_stickers']`).
- Criar figurinha a partir de: (a) imagem (arquivo/galeria), (b) câmera (foto), (c) figurinha **recebida** na conversa.
- Conversão para `.webp` 512×512 — **estática e animada** (libvips).
- Envio nativo de figurinha via **WhatsApp Cloud API** (`type: sticker`).
- Botão + picker no composer desktop (`ReplyBox`/`ReplyBottomPanel`) e mobile (`MobileReplyBox`).
- Bolha de renderização de figurinha (`content_type: 'sticker'`).

**Fora do escopo (não fazer):**
- Giphy / qualquer API externa de figurinhas.
- Pacotes/coleções e tela de Configurações admin (o legado tinha; descartado).
- Serviços de métricas/monitor de cache/performance do legado.
- Status "otimista" com `skip_send_reply` (descartado em favor do pipeline nativo).
- Provedores 360dialog/Evolution e canais não-WhatsApp para envio nativo de figurinha.
- Tela de recorte/zoom manual na criação (MVP usa auto-encaixe; pode vir depois).

## 3. Defaults confirmados

1. Biblioteca **por conta** (compartilhada).
2. Criação por **auto-encaixe** em 512×512 com padding transparente (sem recorte manual no MVP).
3. **Apagar** figurinha: restrito ao **criador ou admin**. Listar/criar/enviar: qualquer agente.

## 4. Estado atual relevante (já existe no código)

- `app/models/message.rb:100` — enum `content_type` já tem `sticker: 11`. **Reusar.**
- `app/javascript/dashboard/components-next/message/constants.js:70` — `CONTENT_TYPES.STICKER = 'sticker'`. **Reusar.**
- Envio outgoing WhatsApp: `Whatsapp::SendOnWhatsappService#send_session_message` → `channel.send_message(source_id, message)` → `Whatsapp::Providers::WhatsappCloudService#send_message`.
- `WhatsappCloudService#send_message` (linhas ~4–30) já ramifica por anexo/tipo. **Adicionar ramo de sticker.**
- Figurinha **recebida** já entra como anexo de imagem (`incoming_message_service_helpers.rb:37` mapeia `sticker → image`).
- `ruby-vips 2.1.4` disponível via gem `image_processing` (libvips).

> **Não existe** hoje: tabela/modelo de sticker, controllers/rotas, services de conversão/envio de sticker, bubble `Sticker.vue`, picker no composer.

## 5. Decisão de arquitetura

### 5.1 Envio = pipeline nativo (Abordagem A — escolhida)

Enviar uma figurinha cria uma **mensagem `outgoing` normal** com `content_type: 'sticker'` e o anexo `.webp`, via `Messages::MessageBuilder`. O fluxo nativo (`SendOnWhatsappService → channel.send_message → WhatsappCloudService#send_message`) já roda e já trata `source_id`/status/echo.

Adiciona-se no `WhatsappCloudService#send_message` um ramo **antes** do ramo de anexos:

```ruby
if message.content_type == 'sticker' && message.attachments.present?
  send_sticker_message(phone_number, message)
elsif message.attachments.present?
  send_attachment_message(phone_number, message)
# ... ramos existentes
```

Rejeitadas: (B) endpoint/serviço dedicado com `skip_send_reply` + status manual (frágil, mais código, risco de duplicar — era o legado); (C) enviar como imagem comum (não vira figurinha nativa).

### 5.2 Armazenamento = tabela `stickers` dedicada

Modelo novo `Sticker` com tabela própria, em vez de sobrecarregar o core `Attachment` com `meta` (como o legado). Aditivo e seguro p/ upstream (CLAUDE.md: preferir arquivo/modelo novo a mexer no core).

## 6. Componentes

### 6.1 Backend — modelo & migration

- **Migration** `create_stickers`:
  - `account_id` (FK, índice), `user_id` (FK criador, nullable), `animated:boolean default false`, timestamps.
- **`app/models/sticker.rb`**:
  - `belongs_to :account`, `belongs_to :user, optional: true`.
  - `has_one_attached :file` (ActiveStorage; o `.webp`).
  - Scope `recent_for(user)` (lê `user.ui_settings['recent_stickers']`, ordena pela lista).
- **`app/policies/sticker_policy.rb`**: `index?/show?/create?/send_sticker? = agente+`; `destroy? = criador || admin`.

### 6.2 Backend — `Stickers::ConverterService`

- **Entrada:** um `file` (upload) **ou** um blob de `Attachment` existente (figurinha recebida).
- **Saída:** `Sticker` com `file` (`.webp` 512×512) anexado e `animated` setado.
- **Lógica (libvips):**
  - Detecta animação na origem (GIF ou webp animado via `Vips::Image.new_from_*` com `n: -1`, `page_height`/`get('n-pages')`).
  - **Estática:** `thumbnail` para caber em 512², compõe sobre canvas transparente 512², exporta `.webp` (alvo ≤100KB; reduz `Q` se preciso: `[80,70,60,50,40,30]`).
  - **Animada:** processa as páginas (frames), redimensiona, exporta `.webp` animado (`n: -1`) com alvo ≤500KB (degrada `Q`; opcionalmente reduz nº de frames se estourar).
  - Falha de otimização animada → fallback para 1º frame estático (não quebra o fluxo).
- **Limites/validação:** input ≤5MB; formatos aceitos: jpeg/png/gif/webp/bmp/tiff. Erros como exceções tratadas no controller.

### 6.3 Backend — controller & rotas

`app/controllers/api/v1/accounts/stickers_controller.rb`, namespace account-scoped:

| Método | Rota | Ação |
|---|---|---|
| GET | `/stickers` (`?recent=true`) | lista biblioteca da conta / recentes do usuário |
| POST | `/stickers` | cria de `file` **ou** `source_attachment_id` |
| DELETE | `/stickers/:id` | remove (criador/admin) |
| POST | `/stickers/:id/send` | body `{conversation_id}`: cria msg outgoing + recentes |

- **`send`**: valida conversa + canal WhatsApp; `MessageBuilder` cria msg `outgoing`, `content_type: 'sticker'`, anexa **o mesmo blob** ActiveStorage do sticker (sem reupload em disco); `append_recent_sticker(user, sticker.id)`. Retorna a mensagem. O job outgoing nativo envia.
- Rotas adicionadas em `config/routes.rb` dentro do bloco de account já existente (preservando rotas Chatwit existentes).

### 6.4 Backend — WhatsApp Cloud

`app/services/whatsapp/providers/whatsapp_cloud_service.rb`:
- `send_sticker_message(phone_number, message)`: pega `message.attachments.first` → bytes do `.webp` → `media_id = upload_media(bytes, 'image/webp')` (cache Redis opcional por `sticker_id:channel`) → `POST #{phone_id_path}/messages` com `{ messaging_product, recipient_type:'individual', to, type:'sticker', sticker:{ id: media_id } }` → `process_response`.
- `upload_media(bytes, content_type)`: `POST #{phone_id_path}/media` (multipart, `messaging_product: 'whatsapp'`), retorna `media_id`.
- Ramo `content_type == 'sticker'` no `send_message` (ver 5.1).

### 6.5 Frontend — bubble

- `app/javascript/dashboard/components-next/message/bubbles/Sticker.vue`: renderiza `content_type 'sticker'` como imagem "solta" (sem fundo de balão), tamanho de figurinha (~128px desktop / ~96px mobile), `object-fit: contain`. Conectar no dispatcher de bubbles de `components-next/message`.
- Figurinhas **recebidas** continuam renderizando como imagem (sem regressão); ganham a ação "Salvar como figurinha" no menu.

### 6.6 Frontend — lógica compartilhada

- `app/javascript/dashboard/api/stickers.js` — client (`get`, `getRecent`, `create`, `createFromAttachment`, `destroy`, `send`).
- `app/javascript/dashboard/composables/useStickers.js` — estado/ações reutilizados por desktop e mobile (lista, recentes, criar, enviar, apagar). "Conectar, não recriar."

### 6.7 Frontend — botão + picker (desktop)

- Botão de figurinha em `app/javascript/dashboard/components/widgets/WootWriter/ReplyBottomPanel.vue` (toolbar do `ReplyBox`), visível em canais WhatsApp.
- `StickerPicker` (popover/drawer): abas "Biblioteca" e "Recentes"; grid; botão "＋ criar"; clicar = enviar.
- **Não alterar** comportamento existente do `ReplyBox` (adição isolada).

### 6.8 Frontend — botão + picker (mobile, isolado)

- Botão de figurinha em `app/javascript/dashboard/components-next/mobile/MobileReplyBox.vue`.
- `components-next/mobile/MobileStickerSheet.vue` (bottom sheet) consumindo `useStickers`.
- Criar via câmera/galeria reaproveitando os inputs de arquivo/câmera já presentes no `MobileReplyBox`.

### 6.9 Frontend — criar & salvar

- **Criar:** "＋" → seletor de imagem (arquivo/câmera) → preview → `POST /stickers` → entra na biblioteca → toca p/ enviar.
- **Salvar recebida:** menu de contexto/long-press na bolha de figurinha recebida → "Salvar como figurinha" → `POST /stickers { source_attachment_id }`.

## 7. Fluxo de dados

**Criar a partir de imagem:**
`UI (file/câmera)` → `POST /stickers (multipart)` → `ConverterService` (libvips → webp 512²) → `Sticker.create + file` → retorna sticker → aparece na biblioteca.

**Salvar figurinha recebida:**
`long-press na bolha` → `POST /stickers { source_attachment_id }` → `ConverterService` lê blob do attachment → webp → `Sticker`.

**Enviar:**
`tocar figurinha` → `POST /stickers/:id/send { conversation_id }` → `MessageBuilder` (outgoing, `content_type sticker`, anexa blob) + recentes → `SendOnWhatsappService` → `WhatsappCloudService#send_message` → ramo sticker → `upload_media` → `POST type:sticker` → `process_response` atualiza `source_id`/status. Bubble `Sticker.vue` renderiza.

## 8. Casos de borda

- **Canal não-WhatsApp:** botão de figurinha oculto (MVP só WhatsApp Cloud).
- **`can_reply?` falso:** mesma regra de qualquer mensagem de sessão (não força figurinha; botão respeita janela 24h como o composer já faz).
- **Animada estoura 500KB:** degrada Q e, se preciso, reduz frames; último recurso = fallback estático (1º frame).
- **Falha no `upload_media`/API:** `process_response` marca status `failed` nativamente (sem tratamento manual).
- **Origem inválida (formato/size):** erro 422 com mensagem i18n; nada é criado.
- **Apagar figurinha já usada:** remove só da biblioteca; mensagens já enviadas permanecem (anexo/echo independem da row `stickers`).

## 9. i18n

- Chaves em `en`, `pt`, `pt_BR` (backend `en.yml`/`*.yml`; frontend `*.json` + `mobile.json` p/ strings mobile). Sem strings cruas.

## 10. Isolamento (regra do fork)

- Mobile: somente `components-next/mobile/` + composable/API compartilhados (não-mobile).
- Desktop: adição isolada no `ReplyBottomPanel`; zero alteração de comportamento do `ReplyBox`.
- Core Chatwoot: não modificar `Attachment`; reutilizar enum `sticker` já presente em `message.rb`; rota/branch adicionados sem remover nada existente.

## 11. Testes (mínimos, focados)

- RSpec `Stickers::ConverterService`: estática (≤100KB, 512²) e animada (≤500KB, preserva animação).
- RSpec `WhatsappCloudService#send_sticker_message`: monta payload `type: sticker` e chama `upload_media`.
- Request spec `POST /stickers/:id/send`: cria mensagem `content_type: 'sticker'` na conversa e adiciona aos recentes.
- (Sem reintroduzir specs dos serviços de métricas/monitor do legado.)

## 12. Lista de arquivos (novos / tocados)

**Novos (backend):**
- `db/migrate/<ts>_create_stickers.rb`
- `app/models/sticker.rb`
- `app/policies/sticker_policy.rb`
- `app/controllers/api/v1/accounts/stickers_controller.rb`
- `app/services/stickers/converter_service.rb`

**Tocados (backend):**
- `config/routes.rb` (rotas `stickers`)
- `app/services/whatsapp/providers/whatsapp_cloud_service.rb` (`send_sticker_message`, `upload_media`, ramo sticker)

**Novos (frontend):**
- `app/javascript/dashboard/api/stickers.js`
- `app/javascript/dashboard/composables/useStickers.js`
- `app/javascript/dashboard/components-next/message/bubbles/Sticker.vue`
- `app/javascript/dashboard/components/widgets/conversation/StickerPicker/StickerPicker.vue`
- `app/javascript/dashboard/components-next/mobile/MobileStickerSheet.vue`

**Tocados (frontend):**
- `app/javascript/dashboard/components/widgets/WootWriter/ReplyBottomPanel.vue` (botão desktop)
- `app/javascript/dashboard/components-next/mobile/MobileReplyBox.vue` (botão mobile)
- dispatcher de bubbles em `components-next/message` (registrar `Sticker.vue`)
- menu de contexto da mensagem (ação "Salvar como figurinha")
- i18n: `*.json`, `mobile.json`, `*.yml`

## 13. Documentação

- Atualizar `chatwitdocs/Chatwoot-Chatwit-mobile.md` (changelog mobile do botão/sheet).
- Criar `chatwitdocs/migration-etapa3-stickers.md` (rotas, services, fluxo) e marcar Etapa 3 como concluída no CLAUDE.md.
