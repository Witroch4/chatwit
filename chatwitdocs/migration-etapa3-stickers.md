# Migration Etapa 3 — Figurinhas (WhatsApp Stickers)

**Data:** 2026-06-14
**Versão Base:** Chatwoot 4.10.1
**Objetivo:** Permitir enviar e receber figurinhas (stickers) do WhatsApp Cloud, com biblioteca por conta e recentes por usuário, tanto no desktop quanto no mobile.

**Docs de referência (spec/plano):**
- Spec/design: `docs/superpowers/specs/2026-06-14-whatsapp-stickers-design.md`
- Plano de execução: `docs/superpowers/plans/2026-06-14-whatsapp-stickers.md`

---

## Resumo da Etapa 3

Esta etapa adiciona suporte completo a **figurinhas do WhatsApp** ao Chatwit:

- Enviar figurinhas de uma biblioteca compartilhada por conta (com recentes por usuário).
- Criar figurinhas a partir de uma imagem do dispositivo, da câmera, ou de um anexo recebido na conversa ("Salvar como figurinha").
- Conversão automática para o formato exigido pelo WhatsApp (webp 512×512) via **libvips**, com suporte a figurinhas estáticas e animadas.
- Renderização visual das figurinhas como bolha sem borda no chat.

**Escopo:** **WhatsApp Cloud only.** Sem Giphy/API externa, sem pacotes (packs) e sem página de administração/configuração de figurinhas.

---

## Escopo Realizado

- [x] Tabela `stickers` + model `Sticker` (`has_one_attached :file`)
- [x] Recentes por usuário em `user.ui_settings['recent_stickers']`
- [x] `StickerPolicy`
- [x] `Stickers::ConverterService` (libvips: estático e animado)
- [x] `Api::V1::Accounts::StickersController` (`index`, `create`, `destroy`, `send_sticker`) + rotas
- [x] Caminho de envio nativo via `content_type: 'sticker'` (sem service de envio separado)
- [x] `WhatsappCloudService#send_sticker_message` + branch `sticker` em `send_message`
- [x] Frontend: `api/stickers.js` + composable `useStickers()`
- [x] Bolha de figurinha `Sticker.vue` (registrada no `Message.vue`)
- [x] Desktop: `StickerPicker.vue` + botão no `ReplyBottomPanel.vue` (ligado no `ReplyBox.vue`)
- [x] Mobile: `MobileStickerSheet.vue` + botão no `MobileReplyBox.vue`
- [x] "Salvar como figurinha" no `MessageContextMenu.vue` (desktop) e `MobileMessageContextMenu.vue` (mobile)
- [x] i18n: `en/conversation.json` (desktop), `en`/`pt`/`pt_BR` `mobile.json`

---

## Backend

### Tabela e Model

- **Migration:** `db/migrate/20260614160609_create_stickers.rb` — cria a tabela `stickers` com `account_id`, `user_id` e `animated` (boolean).
- **Model:** `app/models/sticker.rb` — `belongs_to :account` / `belongs_to :user`, `has_one_attached :file` (o webp convertido). Recentes do usuário ficam em `user.ui_settings['recent_stickers']` (não na tabela `stickers`), permitindo **biblioteca compartilhada por conta** + **recentes por usuário**.
- **Account:** `app/models/account.rb` ganhou `has_many :stickers, dependent: :destroy_async`.

### Policy

- `app/policies/sticker_policy.rb` — autorização padrão do account scope para `index`/`create`/`destroy`/`send_sticker`.

### Conversão (libvips) — `app/services/stickers/converter_service.rb`

Converte a imagem de origem para o formato de figurinha do WhatsApp usando **libvips** (`Vips::Image`). Alvo: `512×512` webp com transparência.

- **Estática:** `thumbnail_buffer` redimensiona para caber em 512×512 (`size: :down`), preenche/centraliza para canvas transparente 512×512 e codifica em webp dentro de **≤ 100 KB** (`STATIC_MAX_BYTES`), reduzindo a qualidade em degraus até caber.
- **Animada (GIF/webp animado):** `thumbnail_buffer` com `option_string: 'n=-1'` (animation-aware: lê todas as páginas) gera webp animado 512×512 dentro de **≤ 500 KB** (`ANIMATED_MAX_BYTES`). Se a otimização animada falhar, há **fallback para o primeiro frame como figurinha estática** (ainda válida para o WhatsApp). A flag `animated` é persistida no `Sticker`.

### Controller e rotas

- `app/controllers/api/v1/accounts/stickers_controller.rb`:
  - `index` — lista a biblioteca da conta + recentes do usuário.
  - `create` — cria a partir de `file` (upload direto) **OU** `source_attachment_id` (anexo já recebido na conversa — "Salvar como figurinha"). Roda pelo `Stickers::ConverterService`.
  - `destroy` — remove a figurinha da biblioteca.
  - `send_sticker` — dispara o envio (cria a mensagem OUTGOING com `content_type: 'sticker'`).
- `config/routes.rb`:
  ```ruby
  resources :stickers, only: [:index, :create, :destroy] do
    post :send_sticker
  end
  ```

### Caminho de envio nativo (link-based)

O envio de uma figurinha é uma **mensagem OUTGOING normal** com `content_type: 'sticker'` + o anexo webp, construída pelo `Messages::MessageBuilder`. A pipeline nativa de saída carrega a mensagem até o branch de sticker do provider — **não há service de envio separado** e **não há `upload_media`**: o envio é **baseado em link** (`download_url` do anexo), exatamente como o caminho de imagem já existente.

- `app/services/whatsapp/providers/whatsapp_cloud_service.rb`:
  - `send_message`: branch `if message.content_type == 'sticker' && message.attachments.present?` → `send_sticker_message`.
  - `send_sticker_message`: posta no WhatsApp Cloud com `type: 'sticker'` e `sticker: { link: attachment.download_url }`.

---

## Frontend

### API e estado

- `app/javascript/dashboard/api/stickers.js` — client de API (list/create/destroy/send).
- `app/javascript/dashboard/composables/useStickers.js` — composable `useStickers()` que centraliza estado e chamadas. **Desktop e mobile reusam o mesmo composable** (nada de lógica reimplementada).

### Renderização

- `app/javascript/dashboard/components-next/message/bubbles/Sticker.vue` — bolha de figurinha **sem borda**, registrada em `components-next/message/Message.vue`. O `Message.vue` também expõe `stickerAttachmentId` para o fluxo "Salvar como figurinha".

### Desktop

- `app/javascript/dashboard/components/widgets/conversation/StickerPicker/StickerPicker.vue` — picker de figurinhas (biblioteca + recentes + "adicionar").
- `app/javascript/dashboard/components/widgets/WootWriter/ReplyBottomPanel.vue` — botão de figurinha (exibido só em WhatsApp).
- `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue` — fiação do picker no composer.
- `app/javascript/dashboard/modules/conversations/components/MessageContextMenu.vue` — ação "Save as sticker" no menu de contexto.

### Mobile (módulo isolado em `components-next/mobile/`)

- `app/javascript/dashboard/components-next/mobile/MobileStickerSheet.vue` — bottom sheet que **reusa `useStickers()`**; lista biblioteca + recentes, envia com um toque e tem botão "+" para criar a partir de imagem/câmera.
- `app/javascript/dashboard/components-next/mobile/MobileReplyBox.vue` — botão de figurinha dentro da pill de input (gate WhatsApp, igual ao desktop).
- `app/javascript/dashboard/components-next/mobile/MobileMessageContextMenu.vue` — ação "Salvar como figurinha".

### i18n

- **Desktop** (`en/conversation.json`): mantido **somente em inglês** (a comunidade traduz os demais idiomas — convenção do repo).
- **Mobile** (`en`/`pt`/`pt_BR` `mobile.json`): bloco `MOBILE.STICKERS` com `TITLE`, `ADD`, `SAVE`, `SAVED`, `SAVE_FAILED`. O módulo mobile é fork exclusivo do Chatwit e por isso embarca pt/pt_BR.

---

## Lista de Arquivos

### Criados

| Arquivo | Descrição |
|---------|-----------|
| `db/migrate/20260614160609_create_stickers.rb` | Migration da tabela `stickers` |
| `app/models/sticker.rb` | Model `Sticker` (`has_one_attached :file`) |
| `app/policies/sticker_policy.rb` | Autorização |
| `app/services/stickers/converter_service.rb` | Conversão libvips (estático + animado) |
| `app/controllers/api/v1/accounts/stickers_controller.rb` | Controller (index/create/destroy/send_sticker) |
| `app/javascript/dashboard/api/stickers.js` | Client de API |
| `app/javascript/dashboard/composables/useStickers.js` | Composable de estado |
| `app/javascript/dashboard/components-next/message/bubbles/Sticker.vue` | Bolha de figurinha |
| `app/javascript/dashboard/components/widgets/conversation/StickerPicker/StickerPicker.vue` | Picker desktop |
| `app/javascript/dashboard/components-next/mobile/MobileStickerSheet.vue` | Bottom sheet mobile |
| `spec/services/stickers/converter_service_spec.rb` | Specs do converter |
| `spec/controllers/api/v1/accounts/stickers_controller_spec.rb` | Specs do controller |
| `spec/services/whatsapp/providers/whatsapp_cloud_service_spec.rb` | Specs do envio (branch sticker — atualizado) |

### Modificados

| Arquivo | Descrição |
|---------|-----------|
| `config/routes.rb` | Rotas `stickers` + `send_sticker` |
| `app/models/account.rb` | `has_many :stickers` |
| `app/services/whatsapp/providers/whatsapp_cloud_service.rb` | Branch `sticker` + `send_sticker_message` |
| `db/schema.rb` | Tabela `stickers` |
| `app/javascript/dashboard/components-next/message/Message.vue` | Registro da bolha + `stickerAttachmentId` |
| `app/javascript/dashboard/components/widgets/WootWriter/ReplyBottomPanel.vue` | Botão de figurinha (WhatsApp) |
| `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue` | Fiação do picker |
| `app/javascript/dashboard/modules/conversations/components/MessageContextMenu.vue` | "Save as sticker" |
| `app/javascript/dashboard/components-next/mobile/MobileReplyBox.vue` | Botão de figurinha mobile |
| `app/javascript/dashboard/components-next/mobile/MobileMessageContextMenu.vue` | "Salvar como figurinha" mobile |
| `app/javascript/dashboard/i18n/locale/en/conversation.json` | Strings desktop (EN) |
| `app/javascript/dashboard/i18n/locale/en/mobile.json` | `MOBILE.STICKERS` (EN) |
| `app/javascript/dashboard/i18n/locale/pt/mobile.json` | `MOBILE.STICKERS` (PT) |
| `app/javascript/dashboard/i18n/locale/pt_BR/mobile.json` | `MOBILE.STICKERS` (PT-BR) |

---

## Verificação Automatizada

- **Backend (rspec):** `spec/services/stickers/converter_service_spec.rb`, `spec/services/whatsapp/providers/whatsapp_cloud_service_spec.rb`, `spec/controllers/api/v1/accounts/stickers_controller_spec.rb` → **31 examples, 0 failures**.
- **Frontend (eslint):** todos os arquivos tocados pela feature → **0 erros** (apenas warnings pré-existentes/aceitáveis: `vue/no-root-v-if` e `@intlify/vue-i18n/no-raw-text` para o caractere `×`).

---

## Manual QA Checklist

Requer app rodando + uma inbox WhatsApp Cloud real (não coberto por teste automatizado).

**Desktop (≥ 768px):**
- [ ] Abrir uma conversa de canal **WhatsApp** → o botão de figurinha aparece no composer.
- [ ] Clicar no botão → o `StickerPicker` abre com biblioteca + recentes.
- [ ] Adicionar uma imagem (estática) → ela é convertida e aparece na biblioteca.
- [ ] Enviar a figurinha → renderiza como bolha **sem borda** e chega no WhatsApp como figurinha **real** (não como imagem).
- [ ] Adicionar e enviar um **GIF animado** → chega como figurinha animada (ou fallback estático do primeiro frame).
- [ ] Botão direito numa **imagem recebida** → "Save as sticker" salva na biblioteca.
- [ ] Confirmar que conversas **não-WhatsApp** não exibem o botão de figurinha.

**Mobile (< 768px):**
- [ ] Botão de figurinha aparece **dentro da pill de input** numa conversa WhatsApp.
- [ ] Tocar → abre o `MobileStickerSheet`; enviar com um toque funciona.
- [ ] Botão "+" cria figurinha a partir de imagem/câmera.
- [ ] "Salvar como figurinha" no menu de contexto da mensagem funciona.

**Regressão (isolamento desktop):**
- [ ] No desktop (≥ 768px) nada do layout/composer mudou de comportamento; o módulo mobile não vaza para o desktop.
