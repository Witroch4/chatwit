# Mobile Dashboard Fixes

Date: 2026-03-14

## 2026-06-15 - Composer 36px (paridade nativa) + faixa preta no rodapé do PWA

### Contexto

Dois bugs visuais no PWA instalado (iOS standalone):

1. **Caixa de input alta.** O usuário reportou a "pílula" do composer alta demais
   vs. o app nativo. Medição com Playwright + Tailwind real provou que o `min-h-[36px]`
   era irrelevante: os botões inline (cadeado/figurinha) são `h-7` (28px), mais altos
   que a textarea (22px); com `items-center`, o botão de 28px + `py-1.5` (12px) + borda
   inflava a pílula para **42px**. O app nativo evita isso posicionando o cadeado
   `absolute`, deixando só a textarea reger a altura (`min-h-9` = 36px).
2. **Faixa preta no rodapé.** Abaixo da barra de abas aparecia uma faixa preta. Causa
   raiz: o `<body>` (`vueapp.html.erb`) nunca teve `background`; no PWA standalone com
   `viewport-fit=cover`, o `h-screen` (100vh) não pinta de forma confiável a safe-area
   inferior, então o body cru (preto) vazava. O `bg-n-background` no root do `App.vue`
   foi adicionado pelo upstream (`ee8cc0b804`), mas o body ficou sem cor — daí "veio
   com um diff web".

### Implementado

- **`components-next/mobile/MobileReplyBox.vue`** (paridade com o nativo):
  - Pílula `py-1.5` → `py-0.5` — com os botões de 28px a pílula fecha em **36px**
    (= `min-h-9` do nativo), mantendo os alvos de toque maiores.
  - Textarea `text-sm`/`placeholder:text-sm` → `text-base`/`placeholder:text-base`
    (16px). Mantém `leading-5` (20px) — o mesmo truque do nativo (`text-base leading-[20px]`):
    fonte de 16px **sem** inflar a altura. 16px também **elimina o zoom-on-focus do iOS**
    (que reaparecia com 14px). Medição confirmou: 14px e 16px dão a mesma pílula de 36px.
- **`app/views/layouts/vueapp.html.erb`**: `<body class="text-slate-600">` →
  `... bg-n-background`. Em dark mode o body vira `rgb(28,29,32)` = **a mesma cor da
  barra de abas** (`bg-n-background`), então a safe-area inferior fica contínua com a
  barra (a barra "desce" até a base do iPhone) e a faixa preta some. Propaga para o
  canvas via regra de propagação de background do body.

### Follow-up (mesmo dia): rodapé do chat usa 100% da base

Pintar a safe-area só mudou a cor da faixa — o `pb-[env(safe-area-inset-bottom)]` do
`MobileReplyBox` continuava empurrando o input ~34px pra cima e comendo altura do chat.
Decisão do usuário: **a base do iPhone pode ser usada 100%, padding inferior = zero**
(só o topo mantém limitação de safe-area). Aplicado:

- `MobileReplyBox.vue`: removido o `pb-[env(safe-area-inset-bottom)]` (e o prop
  `keyboardOpen`, que só existia pra alternar esse padding — virou código morto). O input
  encosta na base; o `py-2` da própria linha já dá ~8px de respiro sobre o home-indicator.
- `MobileChatView.vue`: removido o binding `:keyboard-open`.

### Isolamento

- `MobileReplyBox.vue`: mudança 100% visual e restrita ao componente mobile.
- `vueapp.html.erb`: aditivo. O body não tinha background nenhum; agora adota o token
  do tema (claro `#F7F7F7`, escuro `#1C1D20`). O app desktop preenche por cima
  (`App.vue` `h-screen bg-n-background`), então o body só aparece em safe-area/overscroll
  — sem regressão no desktop, e em dark mode é até uma melhora (sem flash branco/preto).

### Verificação

- Altura medida via Playwright contra o engine real do Tailwind (pílula 42px → 36px).
- Cor do body confirmada no dev server: dark = `rgb(28,29,32)` (igual à barra), claro =
  `rgb(247,247,247)`.
- **Pendente confirmar no PWA instalado (iOS)** — a safe-area só renderiza em standalone real.

## 2026-06-14 - Composer (MobileReplyBox) com aparência tipo WhatsApp

### Contexto

O input de texto do PWA mobile parecia "cortar" o texto e ficava mais estreito/baixo
que o campo do WhatsApp. As causas: fonte abaixo de 16px (`text-sm` no texto e
`text-xs` no placeholder), pílula curta (`min-h-[36px]` + `py-1.5`) e `line-height`
apertado (`h-5 leading-5`). Fonte < 16px ainda fazia o iOS dar zoom na tela ao focar,
comportamento que o WhatsApp nunca tem.

### Implementado (somente `components-next/mobile/MobileReplyBox.vue`)

- Texto e placeholder em 16px (`text-base`), eliminando o zoom-on-focus do iOS e
  igualando o tamanho confortável do WhatsApp.
- Pílula mais alta e folgada: `min-h-[40px]` + `py-2`, com `h-6 leading-6` (24px) no
  textarea para dar respiro vertical ao texto.
- `resizeTextarea` agora parte de `24px` (alinhado ao `leading-6`); o crescimento
  multi-linha até `max-h-[120px]` com scroll permanece igual (~5 linhas, como o WhatsApp).
- Linha de duração do gravador de áudio também ajustada para `min-h-[40px]` para não
  variar a altura da barra ao alternar modos.

### Isolamento

- Mudança 100% visual e restrita ao componente mobile; nenhuma lógica/store/desktop tocada.

## 2026-03-16 - Push notifications duplicadas após reinstalar o PWA

### Contexto

Ao desinstalar e reinstalar o Chatwit PWA, o navegador podia gerar uma nova `browser_push` subscription. O toggle de desligar push removia a inscrição apenas localmente com `unsubscribe()`, sem apagar o registro correspondente no backend. Com isso, o mesmo usuário podia acumular subscriptions Web Push antigas e novas, recebendo duas notificações idênticas para a mesma mensagem.

### Implementado

- O fluxo compartilhado de unsubscribe passou a remover a subscription `browser_push` no backend usando o `endpoint` atual antes de concluir o desligamento.
- O endpoint `DELETE /api/v1/notification_subscriptions` passou a aceitar remoção de Web Push por `endpoint`, sempre escopada ao usuário autenticado.
- O service worker `public/sw.js` agora ignora pushes duplicadas recentes com a mesma combinação de `tag`, título, corpo e URL.

### Resultado

- O PWA deixa de manter subscriptions órfãs nas desativações normais de push.
- Se dois eventos idênticos ainda chegarem no mesmo device, apenas uma notificação é exibida.

## Context

Mobile dashboard mode in the frontend was emitting repeated `MOBILE.*` i18n warnings for Portuguese users and could throw runtime errors when an inbox notification arrived without a complete `primaryActor` or sender metadata payload.

## Implemented

- Added `mobile.json` to `pt_BR` and `pt` dashboard locales.
- Registered the new mobile locale bundle in both Portuguese locale indexes.
- Hardened the shared inbox card against missing sender metadata.
- Guarded inbox navigation when a notification does not include a valid conversation reference.

## Result

- Portuguese mobile UI no longer depends on missing `MOBILE.*` keys.
- Inbox/mobile views fail safely for incomplete notification payloads instead of throwing runtime errors.

## 2026-03-14 - Mobile shell isolation and swipe accessibility

### Context

Mobile mode could still trigger desktop-side warnings during the first render pass on narrow viewports. In practice this surfaced as:

- repeated `SIDEBAR.CONVERSATION_WORKFLOW` i18n warnings in `pt_BR`
- `Lit is in dev mode` noise caused by desktop command bar code being reached during the initial shell swap
- browser accessibility warnings when a hidden swipe action button retained focus inside an `aria-hidden` container

### Implemented

- Stabilized the initial viewport width in `routes/dashboard/Dashboard.vue` using the real `window.innerWidth` as the first width value.
- Added the missing `SIDEBAR.CONVERSATION_WORKFLOW` translation key to both `pt_BR/settings.json` and `pt/settings.json`.
- Updated `components-next/mobile/MobileSwipeableRow.vue` so hidden swipe actions are made inert and removed from tab order instead of relying on `aria-hidden` over focusable buttons.

### Result

- The mobile shell no longer needs to briefly mount desktop navigation state before settling on the mobile layout.
- The `SIDEBAR.CONVERSATION_WORKFLOW` locale warning is removed for Portuguese mobile sessions.
- Swipe action buttons in mobile lists no longer produce the `Blocked aria-hidden on an element because its descendant retained focus` accessibility warning.

## 2026-03-14 - Native-style conversation actions pager

### Context

The mobile conversation screen still behaved like a responsive web page, not like the native Chatwoot app. The missing piece was the in-conversation horizontal gesture that reveals the second actions/details screen.

### Implemented

- Added a two-page horizontal pager inside `MobileChatView.vue`.
- Added `MobileConversationActionsView.vue` to mirror the native conversation actions screen.
- Added mobile-only picker sheets for assignee, team, priority, labels, and participants.
- Enhanced `MobileChatHeader.vue` so the header can open the actions page directly.
- Connected the mobile actions page to the existing stores/actions for status, assignee, team, priority, labels, and participants.

### Result

- Swiping left inside a mobile conversation now reveals a second page aligned with the Chatwoot mobile app structure.
- The mobile actions page reuses the existing backend/store flows instead of introducing parallel business logic.

## 2026-03-14 - Mobile chat bubble sizing and clipping

### Context

Some conversation bubbles in mobile mode were wider than the visual envelope used by the native Chatwoot app. In practice this could clip WhatsApp interactive messages and other rich bubbles on narrow screens.

### Implemented

- Added a mobile-only width clamp in `components-next/mobile/MobileChatView.vue` using the native reference proportion of roughly `300px` for standard bubbles.
- Forced rich bubble internals such as WhatsApp interactive content and rich cards to respect the mobile container width.
- Added safer wrapping for long text inside mobile bubbles.

### Result

- Mobile chat bubbles now stay within the viewport and no longer get cut off on narrow screens.
- The visual proportion is closer to the native Chatwoot app while keeping the existing web stores and message components untouched.

## 2026-03-14 - Mobile conversation pager width regression

### Context

The dedicated mobile conversation view uses a two-page horizontal pager. Each page was being sized with `min-w-full` inside a `w-[200%]` track, so the browser treated each page as the full track width instead of a single viewport. That shifted the chat canvas sideways and made bubbles look clipped.

### Implemented

- Changed the pager track in `components-next/mobile/MobileChatView.vue` from a hard `w-[200%]` rail to a normal full-width flex container.
- Made both pager pages explicit `w-full shrink-0` items so each page maps to exactly one viewport.
- Added a `min-w-0` guard to the message page wrapper so the reused desktop `MessagesView` can shrink correctly inside the mobile pager.

### Result

- The mobile chat page now aligns flush with the viewport instead of rendering on a surface wider than the screen.
- Message bubbles keep the expected native-like proportions without being visually cropped on the right edge.