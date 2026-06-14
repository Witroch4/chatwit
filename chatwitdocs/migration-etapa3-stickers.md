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

---

## Correção 2026-06-14 — Figurinhas animadas + anexo .webp (erro 131053)

Dois bugs distintos, ambos confirmados por evidência de produção (logs do webhook de status + DB), corrigidos:

### 1. "Adicionar à biblioteca" falhava em GIFs animados (timeout)
- **Causa raiz:** o `Stickers::ConverterService` reencodava todos os frames a cada passo de qualidade com `effort: 6`. Um sticker de **50 frames** levava **~48s em produção** (medido), estourando o **`rack-timeout` de 15s** → request abortado → nenhuma figurinha salva. O `createFromFile` não tinha tratamento de erro, então o usuário não via nada ("nao foi").
- **Correção:** caminho animado agora usa `ANIMATED_WEBP_EFFORT = 2` + `ANIMATED_QUALITY_STEPS = [65,50,40,30]`, atingindo ≤500KB em 1-2 passos (**~5s em prod**, bem abaixo do timeout). Fallback: se nem a menor qualidade couber, degrada para o 1º frame estático (sticker garantidamente enviável). `crop: :centre` **não** é usável em animado (colapsa o strip de frames); animado mantém `size: :down`.
- **Feedback:** `createFromFile` agora mostra `STICKERS.SAVED` / `STICKERS.SAVE_FAILED` e ativa `isLoading`.

### 2. "Enviar como anexo" (.webp) falhava — `131053: WebP image uploads are not currently supported`
- **Causa raiz:** o WhatsApp aceita `webp` **somente** como `type: sticker`, nunca como `type: image`. Ao anexar um `.webp` direto (sem ser pela biblioteca), a mensagem ia como `content_type: "text"` → caía no caminho de anexo genérico → `type: image` → rejeitado. Os bytes iam **sem conversão** (589KB crus).
- **Correção:** `WhatsappCloudService` agora roteia qualquer anexo `image/webp` para `send_sticker_message` (`sticker_message?`), e converte anexos webp não-biblioteca para um webp compatível (512px / ≤limite) antes do upload (`sticker_upload_bytes` → `ConverterService#to_webp`). Stickers da biblioteca, já compatíveis, sobem como estão (sem reconverter).

### Lembrete técnico
A validação de figurinha do WhatsApp é **assíncrona**: o envio retorna `wamid` (status "sent") e só depois o webhook de status confirma `delivered` ou `failed` com `error_data.details`. Sempre confira o webhook, não só o "enviado" no dashboard.

---

## Correção 2026-06-14 (parte 2) — Velocidade: pular-se-compatível + conversão async

Investigamos por que uma animação "boba" demora ~5s pra salvar. Medição (arquivo real de 50 frames):
**decodificar 50 frames → ~50MB crus = ~2,9s prod** + **recomprimir (effort:2) = ~1,1s prod**. O gargalo é a *quantidade de imagem* (50 frames), não o código — `effort` alto só piora. Logo, ~5s é o piso da conversão **síncrona**. O fork legado (`StickerImageOptimizerService`) não convertia mais rápido (usava effort:6); ele **mascarava** a latência com UI otimista + cache Redis.

Duas mudanças que atacam a causa de verdade:

### 1. Pular a conversão quando o arquivo já é compatível
`Stickers::ConverterService#compliant?` lê **só o header** (rápido) e, se a fonte já é webp **exatamente 512×512** dentro do limite (≤500KB animado / ≤100KB estático), retorna os bytes **como estão** — passthrough **instantâneo** (medido: 0ms). Beneficia muito o "salvar figurinha recebida" (já vem webp 512²) e re-uploads. Também acelera a conversão de anexos webp no caminho de envio do WhatsApp.

### 2. Conversão em background (fluxo otimista)
Quando precisa **reconverter de verdade** (ex.: o meme de 589KB, 89KB acima do teto):
- `Sticker` ganhou `status` (enum `processing/ready/failed`, migration `add_status_to_stickers`).
- `StickersController#create`: se `compliant?` → converte na hora (`:ready`); senão cria o registro com `:processing`, anexa o **original como preview** e enfileira `Stickers::ConvertJob`, retornando **na hora**.
- `Stickers::ConvertJob` (fila `medium`): converte, troca o arquivo pelo webp compatível, marca `:ready` (ou `:failed`).
- `GET /stickers/:id` (novo) + poll no `useStickers` (`pollUntilReady`, 1,5s) atualizam o card quando fica pronto.
- Picker (desktop + mobile): figurinha em `processing` mostra **spinner** e **não é enviável**; `send_sticker` recusa no backend se não estiver `:ready` (defesa em profundidade).

Resultado: instantâneo pra quase tudo (passthrough), e "parece instantâneo" pro resto (aparece na hora com spinner, converte em background; à prova de GIF gigante, sem risco de timeout).
