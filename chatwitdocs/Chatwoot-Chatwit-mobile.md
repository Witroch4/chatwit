# Chatwit Mobile Module (PWA)

> **Status:** Production
> **Date:** 2026-03-14
> **Base:** Chatwoot 4.10.1
> **Tipo:** Customização exclusiva do fork Chatwit — não existe no Chatwoot upstream
> **Roadmap:** `chatwitdocs/mobile-roadmap.md` — auditoria de paridade vs app nativo + fases de evolução

---

## IDENTIDADE DO FORK — REGRA FUNDAMENTAL

O mobile do Chatwit é um módulo do **nosso fork**, não uma réplica do app nativo oficial do Chatwoot. A referência em `chatwitdocs/chatwoot-mobile-app/` serve apenas para **layout, hierarquia visual e ergonomia**.

Fica proibido portar para o PWA do Chatwit qualquer item do app nativo que reintroduza branding, suporte, serviços ou fluxos próprios do produto Chatwoot. Exemplos proibidos:

- `Chat with us` / widget de suporte do Chatwoot
- prompts, links ou CTAs de suporte do Chatwoot
- branding, copy ou identidade do app oficial
- SDKs, serviços ou integrações que existam só no app nativo oficial

Se um item existir no app nativo, mas não tiver uma contraparte real no Chatwit web/desktop, ele **não deve entrar** no nosso mobile. O critério continua sendo o mesmo: conectar somente funcionalidades já existentes e legítimas do fork Chatwit.

---

## ISOLAMENTO COMPLETO — REGRA FUNDAMENTAL

O módulo mobile opera em **isolamento total** do desktop. Ele é uma **camada visual** que renderiza condicionalmente quando `width < 768px`. As regras abaixo são invioláveis:

### 1. Zero regressão no desktop
O módulo mobile **NUNCA** pode alterar, quebrar ou interferir em qualquer funcionalidade da versão desktop. O desktop é a aplicação principal e deve permanecer 100% intacto. Toda alteração mobile vive exclusivamente em `components-next/mobile/` e no guard `v-if="isSmallScreen"` do `Dashboard.vue`.

### 2. CONECTAR — não recriar
**Todas as funcionalidades solicitadas para o mobile JÁ EXISTEM na versão desktop.** O trabalho no módulo mobile é sempre **CONECTAR** as funções desktop ao layout mobile. Exemplos:

| Pedido mobile | O que já existe no desktop | O que o mobile faz |
|---------------|---------------------------|---------------------|
| Status da conversa (Open/Pending/Snooze/Resolve) | Vuex `conversations/toggleStatus`, `updateConversation` | Conecta os mesmos dispatches a botões/sheet mobile |
| Atribuir agente/time | Stores `agents`, `teams`, actions existentes | Conecta as mesmas actions a um bottom sheet mobile |
| Labels, prioridade | Stores `labels`, `conversationLabels` | Conecta ao layout mobile |
| Push notifications | `pushHelper.js`, `sw.js`, VAPID, `NotificationSubscriptions` API | Conecta o mesmo fluxo a um toggle no settings mobile |
| Detalhes do contato | `ContactPanel.vue`, stores `contacts` | Conecta os dados a uma view mobile |

**A palavra-chave é CONECTAR.** Nunca reimplemente lógica, stores, API calls ou services. Use `useMapGetter`, `store.dispatch`, composables e componentes que o desktop já utiliza.

### 3. Sem dependências externas
- **Push:** Web Push via VAPID (chaves auto-geradas no banco). Sem Firebase, sem Chatwoot Hub, sem app nativo.
- **PWA:** `manifest.json` + meta tags + service worker (`public/sw.js`). Instalável via "Adicionar à Tela de Início" no iOS/Android.
- **Sem service de terceiros:** Tudo roda no próprio servidor Chatwit.

### 4. Estrutura de arquivos
Todo código mobile vive em `app/javascript/dashboard/components-next/mobile/`. Traduções em `locale/*/mobile.json`. Esta documentação em `chatwitdocs/Chatwoot-Chatwit-mobile.md`.

---

## Overview

PWA mobile-first completo para o Chatwit. Quando acessado de um smartphone (screen width < 768px), o app renderiza um layout mobile dedicado com bottom tab navigation: **Inbox**, **Conversations**, **Settings**. A versão desktop permanece 100% inalterada.

## Architecture

### Design Principle

- **Conditional rendering** in `Dashboard.vue`: `<MobileLayout v-if="isSmallScreen" />`
- Desktop sidebar, command bar, and copilot are hidden on mobile
- Mobile layout provides its own navigation via bottom tab bar
- All new code lives in `components-next/mobile/` (per CLAUDE.md: prefer new files over modifying existing ones)
- Reuses existing Vuex stores, composables, and API layers

### Detection

Uses the existing `SMALL_SCREEN_BREAKPOINT: 768` from `constants/globals.js` combined with `useWindowSize()` from `@vueuse/core`. The `isSmallScreen` computed property in `Dashboard.vue` controls which layout renders.

### Navigation

```
Dashboard.vue
├── [Desktop: width >= 768px] → NextSidebar + router-view (unchanged)
└── [Mobile: width < 768px] → MobileLayout.vue
    ├── MobileBottomTabBar (fixed bottom)
    └── Active Tab View:
        ├── Tab 0: MobileInboxView (notifications)
        │   └── (tap) → MobileChatView
        ├── Tab 1: MobileConversationList (conversations)
        │   └── (tap) → MobileChatView
        └── Tab 2: MobileSettingsView (profile/settings)
```

URL-based navigation: Vue Router updates the URL when entering a chat, so browser back button works and links are shareable.

## HAPTICS — CONTRATO TÉCNICO (anti-regressão)

> **Por que isto importa:** o feedback tátil dos botões do PWA dependeu de **três** correções encadeadas até finalmente funcionar em iPhones atualizados. Cada uma é frágil e fácil de quebrar sem perceber (não há erro de compilação — o haptic só fica mudo no aparelho). As invariantes abaixo estão **travadas por testes** — não altere `hapticTap.js`/`useHaptics.js` sem rodá-los.
>
> **Testes:** `components-next/mobile/specs/hapticTap.spec.js` e `composables/spec/useHaptics.spec.js` (`pnpm test <arquivo>`).

### Por que finalmente deu certo (a cadeia completa)

O iOS **não implementa** `navigator.vibrate` (nem no Safari 26). O único caminho web para o Taptic Engine é o controle `<input type="checkbox" switch>` (Safari/iOS 17.4+). Três obstáculos foram resolvidos, nesta ordem:

1. **`navigator.vibrate` não existe no iOS** → `useHaptics.js` togglava um `<input switch>` escondido por script (`label.click()`). Funcionou no iOS 17.4–26.4.
2. **A user activation expira após `await`** → haptic disparado *depois* de um `await` de rede nunca chegava ao Taptic Engine. **Correção:** todo call site mobile chama o haptic **sincronamente, no momento do toque**, antes de qualquer `dispatch`/`await`.
3. **iOS 26.5 patcheou o toggle programático** → `label.click()` por script deixou de disparar o haptic; só um **tap trusted do usuário que aterrissa fisicamente no switch** ainda dispara. **Correção (a que destravou tudo):** a diretiva **`v-haptic-tap`** sobrepõe um `<input type="checkbox" switch>` **transparente** sobre o elemento tocável — o dedo real toca o switch (haptic do sistema) e o clique borbulha para o handler do botão.

### Invariantes travadas pelos testes (NÃO quebrar)

**Diretiva `v-haptic-tap` (`hapticTap.js`) — caminho iOS (sem Vibration API):**
- Injeta um overlay `<input type="checkbox" switch>` **transparente** (`opacity:0`), `position:absolute`, `inset:0` (cobre 100% do host), `aria-hidden="true"`, `tabindex=-1`. *(Se o overlay não cobrir o host inteiro ou não for transparente, o tap não cai no switch → sem haptic.)*
- Promove host `static` para `position:relative` (para o overlay ancorar); host já posicionado é deixado intacto.
- Só **tap trusted** (`event.isTrusted`) chama `notifyTrustedHapticTap()`. Clique sintético/programático é ignorado — espelha a regra da Apple. *(Não troque por um listener que dispare em clique programático: mascara o teste e não reflete o device.)*
- Host `disabled`/`aria-disabled` → toggle cancelado (`preventDefault`), sem feedback em controle morto.
- `unmounted` remove o overlay e limpa o `WeakMap`.

**Diretiva — caminho Android (Vibration API presente):**
- **Não** injeta overlay (no-op). O haptic vem de `navigator.vibrate` via `useHaptics`. *(Injetar o overlay no Android sobreporia um switch clicável invisível sobre os botões.)*

**`useHaptics.js` — caminho programático + supressão:**
- Android: cada método chama `navigator.vibrate` com o padrão UIKit (`light:10`, `medium:25`, `selection:5`, etc.) e **nunca** toca no switch.
- iOS sem tap trusted recente: pulsa o switch escondido (fallback para iOS 17.4–26.4 e para feedback **de gesto** — swipe threshold, pull-to-refresh — onde nenhum tap real atinge um switch; em iOS ≥ 26.5 degrada em silêncio, limitação de plataforma).
- **Supressão de duplo-feedback:** após um tap trusted (`notifyTrustedHapticTap()`), o burst programático do mesmo gesto é suprimido por **400 ms**. Passada a janela, o fallback volta a disparar. *(Sem essa janela, iOS ≤ 26.4 vibra duas vezes por toque.)*

### Regra para qualquer componente mobile novo

Toda superfície tocável que mereça feedback recebe **`v-haptic-tap`** no elemento nativo (`<button>` ou raiz single-root) **E** mantém a chamada `useHaptics()` no handler, **síncrona, antes de qualquer `await`** (cobre Android e o gesto). Nunca dispare haptic depois de um `await`.

## Components Created

All under `app/javascript/dashboard/components-next/mobile/`:

### Core
| Component | Description |
|-----------|-------------|
| `MobileLayout.vue` | Root wrapper: bottom tab bar + active tab view + chat overlay |
| `MobileBottomTabBar.vue` | Fixed bottom nav with 3 tabs + unread badge on Inbox |
| `MobileBackButton.vue` | Reusable back navigation button |

### Conversations Tab
| Component | Description |
|-----------|-------------|
| `MobileConversationList.vue` | Full-screen conversation list with virtual scrolling, assignee tabs, infinite scroll |
| `MobileConversationHeader.vue` | Header with title + filter button |
| `MobileChatView.vue` | Full-screen chat view wrapping existing `MessagesView` + `ReplyBox` |
| `MobileChatHeader.vue` | Chat header with back button + contact avatar + name |

### Inbox Tab
| Component | Description |
|-----------|-------------|
| `MobileInboxView.vue` | Full-screen notification list using existing `InboxCard` |
| `MobileInboxHeader.vue` | Header with title + "Mark all read" button |
| `MobilePullToRefresh.vue` | Touch-based pull-to-refresh wrapper |
| `MobileConversationStatusSheet.vue` | Bottom sheet de situação da conversa no mobile, aberto via swipe action `Status` |

### Settings Tab
| Component | Description |
|-----------|-------------|
| `MobileSettingsView.vue` | Profile section + availability toggle + settings list + logout |
| `MobileSettingsHeader.vue` | Header with title |
| `MobileAvailabilityToggle.vue` | Online/Busy/Offline status toggle |

### Shared
| Component | Description |
|-----------|-------------|
| `MobileBottomSheet.vue` | Reusable bottom sheet modal (teleported to body) |
| `MobileFilterSheet.vue` | Conversation filter sheet (status, assignee, sort) |

## Files Modified

| File | Change |
|------|--------|
| `routes/dashboard/Dashboard.vue` | Added `MobileLayout` import + conditional render in template |
| `tailwind.config.js` | Added `slide-up` keyframe + animation for bottom sheets |
| `public/manifest.json` | Enhanced for PWA: name, display, orientation, theme_color |
| `app/views/layouts/vueapp.html.erb` | Added PWA meta tags (apple-mobile-web-app-capable, viewport-fit=cover) |
| `i18n/locale/en/index.js` | Added mobile.json import |
| `i18n/locale/en/mobile.json` | New file with all mobile UI strings |

## Existing Code Reused

| Component/Utility | From |
|-------------------|------|
| `ConversationCard.vue` | `components/widgets/conversation/ConversationCard.vue` |
| `InboxCard.vue` | `components-next/Inbox/InboxCard.vue` |
| `MessagesView.vue` | `components/widgets/conversation/MessagesView.vue` |
| `ChatTypeTabs.vue` | `components/widgets/ChatTypeTabs.vue` |
| `Avatar.vue` | `components-next/avatar/Avatar.vue` |
| `Spinner.vue` | `components-next/spinner/Spinner.vue` |
| `IntersectionObserver.vue` | `components/IntersectionObserver.vue` |
| `useWindowSize()` | `@vueuse/core` |
| `useUISettings()` | `composables/useUISettings` |
| `useAccount()` | `composables/useAccount` |
| `useMapGetter()` | `composables/store` |
| Vuex stores | conversations, notifications, auth |

## PWA Support

- `manifest.json` enhanced with `display: standalone`, `orientation: portrait`
- Meta tags added: `apple-mobile-web-app-capable`, `mobile-web-app-capable`, `viewport-fit=cover`
- Users can "Add to Home Screen" on iOS/Android for app-like experience
- No service worker in MVP (planned for future offline support)

## Styling

- **Tailwind only** (no custom CSS, no scoped CSS)
- Safe area handling: `pb-[env(safe-area-inset-bottom)]` for notched devices
- Dark mode: all components use `dark:` Tailwind variants
- RTL support: uses `ltr:` / `rtl:` classes where applicable
- Bottom tab bar: fixed position, z-50, border-top separator
- Bottom sheet: slide-up animation via Tailwind keyframes

## Testing Checklist

1. Open browser DevTools → iPhone/Android viewport → bottom tab bar appears, sidebar hidden
2. Tab switching works between Inbox, Conversations, Settings
3. Tap conversation → full-screen chat → back button returns to list
4. Notifications load → tap → opens conversation → mark as read
5. Settings: profile displays, availability toggle works, logout works
6. Desktop (>= 768px): normal layout with sidebar, no mobile components
7. Dark mode renders correctly
8. PWA: "Add to Home Screen" prompts correctly on mobile browsers

---

## Roadmap: Future Improvements

### Phase 2: Enhanced Mobile UX
- [x] Swipe actions on conversation/notification rows (swipe to resolve, delete)
- [x] Gesture-based navigation (swipe right to go back)
- [x] Haptic feedback on interactions
- [x] Improved keyboard handling (auto-scroll on input focus)

### Phase 3: Rich Features
- [ ] Voice message recording in mobile chat
- [ ] Contact detail modal in mobile
- [ ] Conversation assignment/transfer from mobile
- [ ] Mobile-optimized search with recent searches
- [ ] Inline image/file previews optimized for mobile

### Phase 4: PWA Advanced
- [ ] Service worker for offline support
- [ ] Push notifications via Web Push API
- [ ] Background sync for messages
- [ ] PWA install prompt UI
- [ ] App shortcuts in manifest

### Phase 5: Performance
- [ ] Route-based code splitting for mobile components
- [ ] Image lazy loading and progressive rendering
- [ ] Skeleton loading states for all views
- [ ] Virtualized list for large conversation/notification lists

### Phase 6: Platform Parity
- [ ] All settings pages accessible from mobile
- [ ] Contact/company views on mobile
- [ ] Reports summary view on mobile
- [ ] Campaign management on mobile
- [ ] Help center access on mobile

---

## Changelog

### 2026-08-02 — Boot do PWA: fim da tela branca/preta e do congelamento na abertura

Sintoma relatado: ao abrir o PWA no celular a tela ficava totalmente branca ou preta e só depois começava a carregar; às vezes travava no preto e só carregava depois de fechar e reabrir o app. Quatro causas independentes, todas corrigidas:

- **Congelamento (causa raiz).** A navegação no `public/sw.js` era **network-first sem timeout**: o fallback para o cache só rodava se o `fetch` **rejeitasse**, e num rádio móvel acordando esse fetch fica pendurado dezenas de segundos antes de falhar — daí a tela preta travada que "some" ao matar e reabrir o app. Agora a rede corre contra `NAVIGATION_NETWORK_TIMEOUT_MS` (2s): passou disso, o shell cacheado é pintado na hora e a resposta fresca é revalidada em background via `event.waitUntil` (os assets com hash que aquele shell referencia vivem no mesmo cache, então o app fica coerente). `navigationPreload` habilitado no `activate` para a navegação começar em paralelo com o boot do worker, `/` entrou no precache (garante fallback já na instalação do SW) e o `cache.put` da navegação ganhou `.catch` (rejeita em respostas redirecionadas).
- **Tela em branco até o Vue montar.** `app/views/layouts/vueapp.html.erb` tinha `<div id="app"></div>` vazio — todo pixel vinha do bundle, e o mount acontece em `window.onload` (espera **todos** os subrecursos). Agora o `#app` traz um splash inline (CSS inline + SVG de pétalas do loader da marca, zero requests extras) que o Vue remove sozinho: `app.mount()` do Vue 3.5 faz `container.textContent = ""` antes de renderizar. Um `<style>`/`<script>` inline no `<head>` também pinta o fundo certo (`#f7f7f7`/`#1c1d20`, espelhando `--background-color`) já no primeiro frame, lendo `localStorage.color_scheme` com a mesma regra do `setColorTheme()` — acaba o flash claro antes do tema escuro aplicar.
- **Splash nativo do iOS.** Não existia nenhum `apple-touch-startup-image`: com `apple-mobile-web-app-status-bar-style: black-translucent`, o iOS mostrava preto puro até o HTML pintar. Novo `script/generate_pwa_splash.py` gera 22 imagens (11 iPhones × claro/escuro) em `public/splash/` **e** o parcial `app/views/layouts/_pwa_splash.html.erb` com os `<link>`/media queries — a tabela de devices no script é fonte única para imagem e markup. A marca fica sobre um tile branco arredondado nos dois temas porque seu traço mais escuro (`#003c55`) sumiria no fundo escuro.
- **SW registrado tarde demais.** `verifyServiceWorkerExistence()` só rodava dentro de `initializeAccount` (pós-login) e ainda exigia `PushManager`, que o iOS só expõe a PWA instalado — ou seja, o cache do shell demorava a esquentar. Novo `registerServiceWorker()` em `helper/pushHelper.js` registra o worker sem depender de push, chamado no `mounted()` do `App.vue`; `verifyServiceWorkerExistence` passou a reusá-lo e manteve o contrato do callback para o fluxo de push.

Validação: `pnpm eslint` limpo nos arquivos tocados e `spec/controllers/dashboard_controller_spec.rb` verde (4/4). O parcial de splash fica dentro do bloco `DISPLAY_MANIFEST` — mesmo gate dos `apple-touch-icon`/`manifest.json` já existentes — e emite os 22 links quando ligado. Desktop intocado: o splash é substituído no mount e o SW só ganhou timeout no caminho que já era dele.

### 2026-06-15 — Toggle de tema (Claro/Escuro/Sistema) no settings mobile

Seletor segmentado de tema em `MobileSettingsView.vue`, logo abaixo de Disponibilidade. **Conecta** (não recria) o mesmo mecanismo do desktop: lê/grava `LocalStorage[LOCAL_STORAGE_KEYS.COLOR_SCHEME]` (`light`/`dark`/`auto`) e aplica via `setColorTheme()` de `helper/themeHelper.js` — a escolha fica em sincronia entre mobile e desktop, e o modo `auto` segue `prefers-color-scheme` (re-aplicado pelo listener do `App.vue`). i18n em `MOBILE.SETTINGS.APPEARANCE/THEME_LIGHT/THEME_DARK/THEME_SYSTEM` (en/pt/pt_BR). Desktop intocado.

### 2026-06-14 — Figurinhas (stickers) no composer mobile

Entrega mobile da feature de figurinhas do WhatsApp (Etapa 3 da migração — doc completa em `chatwitdocs/migration-etapa3-stickers.md`).

- **Botão de figurinha no composer:** novo botão dentro da pill de input em `components-next/mobile/MobileReplyBox.vue`, exibido **apenas** em conversas de canal WhatsApp (mesmo gate do desktop). Abre o sheet de figurinhas.
- **`components-next/mobile/MobileStickerSheet.vue`:** bottom sheet que **reusa o composable `useStickers()`** (mesmo client de API/estado do desktop — nada de lógica reimplementada). Lista a biblioteca da conta + recentes do usuário, permite enviar com um toque e tem um botão "+" (`MOBILE.STICKERS.ADD`) para criar figurinha a partir de imagem/câmera. O envio passa pelo pipeline nativo de mensagem (`content_type: 'sticker'`), idêntico ao desktop.
- **"Salvar como figurinha" no menu mobile:** `components-next/mobile/MobileMessageContextMenu.vue` ganhou a ação (`MOBILE.STICKERS.SAVE`) para salvar uma imagem/figurinha recebida na biblioteca, via `stickerAttachmentId` exposto pelo `Message.vue`.
- **Renderização:** figurinhas chegam como bolha sem borda via `components-next/message/bubbles/Sticker.vue` (componente compartilhado desktop/mobile, registrado no `Message.vue`).

Chaves `MOBILE.STICKERS.*` em `en`/`pt`/`pt_BR`. Escopo WhatsApp Cloud only. Todo o código mobile vive em `components-next/mobile/` — desktop intocado (isolamento total).

### 2026-06-13 — Fix: fundo branco "estourando" por trás do chat em tema escuro

**Sintoma:** no tema escuro, o fundo atrás do chat aparecia branco — embaixo da view de ações, nas bordas e principalmente durante o "page peel" (swipe entre mensagens e ações).

**Causa:** o container do pager em `MobileChatView.vue` tinha um **gradiente claro hardcoded** (`#f8fafc → #eef2f7`) sem variante dark. O backdrop escuro sobreposto (`bg-slate-950`) ia no máximo a `opacity 0.08` (`pagerBackdropStyle`), então o fundo permanecia ~92% claro mesmo no escuro. A pill de dica "Deslize para detalhes" também era `bg-white/80` fixa.

**Correção:** variante `dark:` no gradiente do pager (slate-900 → slate-950, casando com `bg-n-surface-1`/`bg-slate-950` do tema escuro) e `dark:bg-slate-800/80` na pill. As bolinhas dos toggles seguem `bg-white` de propósito (corretas nos dois temas). Mudança só de classes Tailwind em 1 arquivo do módulo mobile — desktop intocado.

### 2026-06-12 — Fix: troca de aba não recarrega mais do zero (cache + websocket, igual app nativo)

**Sintoma:** cada toque em Inbox/Conversas/Settings deixava a tela branca e recarregava tudo do zero — sem cache, sem reuso do websocket. O app nativo carrega uma vez e depois só atualiza via websocket.

**Causa:** as três abas em `MobileLayout.vue` eram renderizadas com `v-if`/`v-else-if`/`v-else`, então cada troca **desmontava e remontava** a view. No remount, o `onMounted` da lista chamava `fetchConversations()` → `emptyAllConversations` (apagava a lista da store) → `chatListLoading` true → spinner (tela branca) → refetch completo da API. O websocket (ActionCable) já mantém a store de conversas/notificações fresca **globalmente**, então a destruição dos dados era gratuita.

**Correção:** envolver as três views em **`<KeepAlive>`**. Cada aba agora monta e busca **uma única vez**; ao voltar, é reativada do cache (sem remount, sem `emptyAllConversations`, sem spinner) renderizando o que o websocket manteve atualizado. Bônus: a posição de scroll de cada aba é preservada. Comportamento idêntico ao app nativo (load-once + live-update). Mudança de 1 arquivo, só no módulo mobile — desktop intocado.

### 2026-06-12 — Testes anti-regressão de haptics + contrato técnico documentado

Confirmado em aparelho: os botões do PWA finalmente vibram em iPhones atualizados (iOS 26.5+). Para travar o mecanismo (que dependeu de 3 correções encadeadas e quebra silenciosamente — sem erro de build, só fica mudo no device), foram adicionados testes e uma referência técnica durável:

- **`components-next/mobile/specs/hapticTap.spec.js`** (10 testes) — trava o contrato da diretiva `v-haptic-tap`: overlay `<input switch>` transparente/full-size/`aria-hidden`/`tabindex=-1`, promoção de host `static`→`relative`, **só tap trusted** chama `notifyTrustedHapticTap()` (clique sintético é ignorado), guarda de host `disabled`/`aria-disabled`, limpeza no `unmounted`, e **no-op no Android** (Vibration API presente → sem overlay).
- **`composables/spec/useHaptics.spec.js`** (4 testes) — trava o caminho programático: Android vibra com o padrão UIKit e nunca toca no switch; iOS pulsa o switch escondido como fallback; e a **supressão de 400 ms** após tap trusted (anti duplo-feedback em iOS ≤ 26.4) com reativação após a janela.
- **Seção "HAPTICS — CONTRATO TÉCNICO (anti-regressão)"** no topo deste doc explica a cadeia completa (vibrate inexistente → user activation expira após `await` → patch do iOS 26.5) e lista as invariantes que os testes protegem.

Sem mudança de código de produção — apenas testes (`app/**/spec*`) e documentação. Desktop intocado.

### 2026-06-11 — Lote H do roadmap: share target Android (compartilhar PARA o Chatwit)

Item 17 do plano de execução (`chatwitdocs/mobile-roadmap-execution-plan.md`):

- **`share_target` no `public/manifest.json`** (GET com `title`/`text`/`url` — texto/URL no MVP; arquivos exigiriam POST + handler no SW, fora do happy path). Android passa a listar o Chatwit no share sheet de outros apps; iOS/desktop ignoram o campo silenciosamente.
- **Captura do share:** novo `components-next/mobile/mobileShareTarget.js` captura `?mobile_share=1&title&text&url` no load do módulo (mesmo racional do `mobileDeepLink.js`: os redirects de boot do router descartam a query antes do `MobileLayout` montar) e expõe `consumeMobileShareText()` + ponte de prefill (`setShareComposerPrefill`/`consumeShareComposerPrefill`).
- **Sheet "Compartilhar em...":** `MobileLayout.vue` consome o share no mount, vai para a tab Conversas e abre o `MobileActionPickerSheet` **existente** (busca, avatar e `v-haptic-tap` já embutidos) listando as 20 conversas mais recentes do getter `getAllConversations` (ordenadas por `last_activity_at`). Sem componente novo de UI.
- **Prefill sem envio automático:** ao escolher a conversa (`selection()` síncrono no handler), navega com `?focus_reply=1` e o `MobileChatView.vue` anexa o texto compartilhado ao emit `FOCUS_REPLY_BOX` já existente — o `MobileReplyBox` já suportava `payload.prefill`, zero mudança no composer.

Chaves `MOBILE.SHARE_TARGET.*` em `en`/`pt`/`pt_BR`; desktop intocado (manifest é plataforma-neutro e o restante vive em `components-next/mobile/`). Item 17 marcado como entregue no roadmap.

### 2026-06-11 — Lote G do roadmap: shell offline + fila offline de envio

Itens 14 e 15 do plano de execução (entregues antes de D/E/F por serem independentes):

- **Shell offline (item 14).** `public/sw.js` ganhou cache versionado `chatwit-shell-v1`: navegações são **network-first** com fallback ao cache (online o comportamento é byte-idêntico; offline o app abre com o último HTML servido), assets de build (`/vite/`, `/packs/`) são **stale-while-revalidate**, e `/api/`/`/cable` nunca passam pelo cache. Versões antigas do cache são limpas no `activate`.
- **Snapshot de conversas offline (item 14).** `MobileConversationList.vue` persiste um snapshot leve (30 conversas: nome, preview, timestamp, status) em `localStorage` a cada atualização da lista; sem rede e sem dados na store, a lista renderiza o snapshot somente-leitura com banner âmbar "Sem conexão" (`useOnline` do `@vueuse/core`).
- **Fila offline de envio (item 15).** Novo `components-next/mobile/useOfflineOutbox.js`: mensagens de **texto** enviadas sem rede entram numa fila em `localStorage` (toast "será enviada quando a rede voltar") e são drenadas em ordem pelo MESMO `createPendingMessageAndSend` do envio normal quando o evento `online` dispara (flush montado no `MobileLayout.vue`, com toast de confirmação). Falhas pós-flush seguem o fluxo padrão de mensagem failed/retry. **Limitação documentada:** anexos não entram na fila (objetos `File` não são serializáveis) — envio com anexo offline mostra o erro normal.

Chaves `MOBILE.OFFLINE.*` em `en`/`pt`/`pt_BR`. Desktop intocado: SW só adiciona handlers (push segue idêntico) e o restante vive em `components-next/mobile/`.

### 2026-06-11 — Lote F do roadmap: View Transitions lista↔chat (item 18)

Transição de página com sensação nativa entre a lista de conversas e o chat, usando a **View Transitions API** (cross-fade de root, Chrome 111+/Safari 18+). Progressive enhancement puro: em browsers sem `document.startViewTransition`, a navegação roda exatamente como antes — zero mudança de comportamento.

- **Helper novo:** `components-next/mobile/viewTransition.js` — `withViewTransition(navigate)` envolve a navegação com `document.startViewTransition`, aguardando a promise do router + `nextTick()` para a API capturar o novo DOM; `afterNextNavigation(router)` resolve após a próxima navegação concluída (com timeout de segurança de 300ms), necessário porque `router.back()` não retorna promise.
- **Pontos de navegação envolvidos (todos em `MobileLayout.vue`):**
  - `onOpenConversation` — lista→chat (usado pelas tabs Inbox e Conversas via emit `open-conversation`);
  - `onBack` — chat→lista, **apenas quando o back vem do botão do header**. Quando o back vem do gesto de swipe-back (`isChatSwiping`), a navegação segue sem view transition, pois o `useSwipeBack` já anima a saída do chat (slide Liquid Glass) — evita animação dupla.
- **Sem CSS novo:** ficou só o cross-fade de root padrão da API (sem `::view-transition-*` nem `view-transition-name` por elemento), eliminando qualquer risco de vazar estilo para o desktop.
- **Isolamento desktop:** o helper só é invocado por `MobileLayout.vue`, que renderiza exclusivamente sob `isSmallScreen` (<768px) — o desktop nunca executa `startViewTransition`. Haptics inalterados (nenhum handler de toque foi movido para depois de `await`).

### 2026-06-11 — Lote F do roadmap: ações no push auditadas como entregues (item 13)

Quarta leva do plano de execução (`chatwitdocs/mobile-roadmap-execution-plan.md`). A auditoria pedida pela Task 13 confirmou que o fluxo completo de ações nos push notifications **já está implementado e testado** — nenhum código novo foi necessário:

- **Responder (inline reply, Android/Chrome):** `public/sw.js` já trata `action === 'reply'` com o texto de `event.reply`, postando via `fetch` em `POST /api/v1/accounts/:account_id/conversations/:conversation_id/messages` com as credenciais DeviseTokenAuth persistidas no IndexedDB (`chatwit-pwa-auth`) pelo `dashboard/helper/swAuthBridge.js`. Sem texto (iOS) ou sem auth, fallback abre o PWA com `focus_reply=1`, que o `MobileChatView.vue` consome para focar o composer.
- **Marcar como lida:** `action === 'mark_read'` faz `PATCH /api/v1/accounts/:account_id/notifications/:notification_id` (mesmo endpoint do app) e o badge do ícone é recalculado.
- **Backend:** `app/services/notification/push_notification_service.rb` já envia `reply_enabled`, `notification_id`, `labels` e `sender` no payload — os botões renderizam sem mudança no servidor.
- **Validação:** `pwaPushNotification.spec.js` (27 testes) + `swAuthBridge.spec.js` (7 testes) passando. Falta apenas o teste manual em Android físico (push com app fechado → Responder/Marcar como lida).

Item 13 do roadmap marcado como entregue; iOS ignora `Notification.actions` por plataforma (sem fallback necessário).

### 2026-06-11 — Lote C do roadmap: detalhes do contato + labels do contato

Terceira leva do plano de execução (`chatwitdocs/mobile-roadmap-execution-plan.md`), itens 3 e 9:

- **Tela de detalhes do contato (item 3).** Novo `MobileContactDetailsView.vue` (página slide-in sobre o chat, registrada no `MobileChatView.vue` com `Transition` translate-x): hero com avatar/nome + ações rápidas ligar/e-mail (`tel:`/`mailto:`), card de informações (telefone, e-mail, empresa, localização via `additional_attributes`), edição mínima (nome/e-mail/telefone) em bottom sheet, e **conversas anteriores** do contato com navegação direta. Stores desktop conectados: `contacts/show`, `contacts/update`, `contacts/getContact`, `contactConversations/get`/`getContactConversation` (mesmos do `ContactPanel.vue`).
- **Labels do contato (item 9).** Seção de labels na mesma tela reusando `MobileMultiPickerSheet` (opções de `labels/getLabels`, seleção de `contactLabels/getContactLabels`) e aplicando via `contactLabels/update` — fluxo idêntico ao desktop.
- **Entrada:** novo card do contato no topo do `MobileConversationActionsView.vue` (avatar + nome + telefone/e-mail + "Ver"), emitindo `openContact` para o chat abrir a página.

Haptics em todas as superfícies novas (`v-haptic-tap` + haptic síncrono); chaves `MOBILE.CONTACT.*` em `en`/`pt`/`pt_BR`; desktop intocado (tudo em `components-next/mobile/`).

### 2026-06-11 — Lote D (Task 1): @menções em notas privadas

Item 1 do roadmap (`chatwitdocs/mobile-roadmap-execution-plan.md`, Lote D):

- **`MobileMentionSheet.vue` (novo).** Lista de agentes ancorada acima do composer (`absolute bottom-full` no `MobileReplyBox.vue`, que fica acima do teclado via `useKeyboardResize` já existente). Conecta o MESMO getter desktop usado pelo `TagAgents.vue`: `agents/getVerifiedAgents` (dados já carregados pelo `agents/get` que o `MobileChatView.vue` despacha no mount), filtrado pelo termo digitado após o `@`. Avatar reusa `components-next/avatar/Avatar.vue` (o mesmo do TagAgents desktop).
- **`MobileReplyBox.vue`.** No `input` do textarea, quando o modo nota privada está ativo (`effectivePrivate`), o trecho até o cursor é testado com `/@([\w]*)$/`; match abre o sheet com o termo. Ao selecionar, o `@termo` é substituído pelo MESMO markdown de menção que o editor desktop serializa (`@chatwoot/prosemirror-schema` `serializer.js`/`schema.js`): `[@Nome](mention://user/<id>/<encodeURIComponent(nome)>)`, e o foco volta ao textarea com o cursor após a menção. Menção indisponível em resposta pública (sheet fecha ao destravar o cadeado) — mesmo comportamento do desktop, onde o fluxo de mention só existe em nota privada. O backend processa a notificação do agente mencionado pelo mesmo pipeline de sempre (nenhuma chamada nova).
- **i18n:** chaves `MOBILE.MENTIONS.*` (`TITLE`, `EMPTY`) em `en`/`pt`/`pt_BR`.

Haptics: linhas de agente com `v-haptic-tap` + `selection()` síncrono no handler. Isolamento preservado: mudanças só em `components-next/mobile/` + `locale/*/mobile.json`; nenhum componente/store desktop alterado.

### 2026-06-11 — Lote D (Task 2): busca de conversas, mensagens e contatos

Item 2 do roadmap (`chatwitdocs/mobile-roadmap-execution-plan.md`, Lote D):

- **`MobileSearchView.vue` (novo).** View fullscreen (Teleport no body, acima do tab bar) com input autofocus no topo e debounce de 300ms via `useDebounceFn` do `@vueuse/core`. Conecta o MESMO store desktop `conversationSearch`: dispatch `conversationSearch/fullSearch` com `{ q, page: 1 }` (precedido de `clearSearchResults`, igual ao `SearchView.vue` desktop, já que as mutations de resultado são append-only) e `clearSearchResults` no unmount/fechar. Resultados via getters `getConversationRecords`, `getMessageRecords`, `getContactRecords` e `getUIFlags`, em 3 grupos (Conversas / Mensagens / Contatos). Tap em conversa ou mensagem reusa a navegação por URL da lista (`openConversation` → `inbox_conversation` no `MobileLayout.vue`). Estados: dica "digite para buscar", carregando (`MobilePetalLoader` spinning) e "sem resultados" (baseado em `isSearchCompleted`). Contatos são exibidos como informação (nome + e-mail/telefone) sem navegação — o registro de contato da busca não carrega conversa associada e o mobile não tem tela de contato; nada de lógica paralela foi criada.
- **`MobileConversationHeader.vue`.** Ícone de lupa ao lado do filtro emitindo `openSearch`; `MobileConversationList.vue` apenas abre/fecha a view e re-emite `openConversation`.
- **i18n:** chaves `MOBILE.SEARCH.*` em `en`/`pt`/`pt_BR`.

Haptics: lupa, voltar, limpar e resultados com `v-haptic-tap` + haptic síncrono no handler (`light()`/`selection()`). Isolamento preservado: nenhum arquivo desktop tocado — tudo em `components-next/mobile/` + `locale/*/mobile.json`.

### 2026-06-11 — Lote E do roadmap: execução de macros na conversa e preferências de notificação

Itens 7, 8, 10 e 11 do plano de execução (`chatwitdocs/mobile-roadmap-execution-plan.md`):

- **Execução de macros (item 7).** Novo `MobileMacrosSheet.vue` conectando a store desktop `macros` exatamente como o `MacroItem.vue` do desktop: `macros/get` no open do sheet, lista via getter `macros/getMacros`, tap em uma macro despacha `macros/execute` com `{ macroId, conversationIds: [conversationId] }` (mesma assinatura de `api/macros.js`), com o MESMO tracking `CONVERSATION_EVENTS.EXECUTED_A_MACRO` do desktop, spinner na linha durante a execução e toast de sucesso/erro via `useAlert`. Nova linha "Macros" na seção "Mais ações" do `MobileConversationActionsView.vue`, seguindo o padrão das linhas mute/share. Chaves `MOBILE.MACROS.*` em `en`/`pt`/`pt_BR`.
- **Preferências de notificação (item 8).** Novo `MobileNotificationPrefsView.vue` (página full-screen via Teleport, header com `MobileBackButton`) conectando a store desktop `userNotificationSettings` exatamente como `NotificationPreferences.vue` do desktop: `userNotificationSettings/get` no mount, flags via getters `getSelectedEmailFlags`/`getSelectedPushFlags`, toggles agrupados em E-mail/Push usando os MESMOS `NOTIFICATION_TYPES` de `settings/profile/constants.js` (labels reusam as chaves desktop `PROFILE_SETTINGS.FORM.NOTIFICATIONS.TYPES.*`, flags SLA escondidas sem o feature flag `FEATURE_FLAGS.SLA`, igual ao desktop). Cada toggle despacha `userNotificationSettings/update` com o set completo de flags (mesmo contrato `selectedEmailFlags`/`selectedPushFlags`), com toast de erro reaproveitando `PROFILE_SETTINGS.FORM.API.UPDATE_ERROR`. Nova linha "Notificações" na lista do `MobileSettingsView.vue` (reusa a chave `MOBILE.SETTINGS.NOTIFICATIONS` já existente). Chaves novas `MOBILE.NOTIF_PREFS.*` (título e títulos de grupo) em `en`/`pt`/`pt_BR`.

- **Read receipts completos — ✓✓ azul (item 11).** Entregue por verificação de conexão, sem código novo. O chat mobile reusa o stack desktop de bolhas (`MessagesView` → `MessageList` → `Message` → `bubbles/Base.vue` → `MessageMeta` → `MessageStatus.vue`), que já renderiza o mapeamento canônico completo dirigido por `message.status` do payload: **sent = ✓ cinza** (`i-lucide-check`, `text-n-slate-10`), **delivered = ✓✓ cinza** (`i-lucide-check-check`), **read = ✓✓ azul** (`text-[#7EB6FF]`), com o gating por canal do `MessageMeta` (WhatsApp/Twilio/SMS/Facebook/Instagram/TikTok/API/Line/Web Widget) e relógio para `progress`. As bolhas ricas do fork (`WhatsAppInteractive.vue`, `RichCards.vue`) também passam por `BaseBubble`/`MessageMeta`, então templates e mensagens interativas exibem os mesmos ticks. O módulo mobile não desenha tick próprio e o CSS do `MobileChatView.vue` não oculta o meta — paridade com o `DeliveryStatus.tsx` do app nativo já garantida por reuso, zero mudança de código e desktop intocado.

- **Transcript por e-mail (item 10).** Nova linha "Enviar transcrição por e-mail" na seção "Mais ações" do `MobileConversationActionsView.vue`, abrindo um mini-sheet (`MobileBottomSheet`) com `<input type="email">` pré-preenchido com o e-mail do agente atual (getter `getCurrentUser`) e botão Enviar (desabilitado quando o e-mail é inválido, spinner durante o envio). O envio despacha a MESMA action desktop `sendEmailTranscript` de `store/modules/conversations/actions.js` (referência `EmailTranscriptModal.vue`), com toast de sucesso/erro via `useAlert`. Chaves `MOBILE.ACTIONS.MORE.TRANSCRIPT*` em `en`/`pt`/`pt_BR`.

Haptics: linha "Macros" e itens do sheet com `v-haptic-tap` + `medium()` síncrono antes do dispatch; toggles de notificação e linhas da lista de settings com `v-haptic-tap` + `selection()` síncrono no handler; linha e botão enviar do transcript com `v-haptic-tap` + `medium()` síncrono antes do `await`. Desktop intocado — mudanças em `components-next/mobile/` e `locale/*/mobile.json`.

### 2026-06-11 — Lote B do roadmap: lightbox touch e snooze customizado

Segunda leva do plano de execução (`chatwitdocs/mobile-roadmap-execution-plan.md`):

- **Lightbox de imagens com gestos touch (item 4).** A bolha de imagem do components-next já abria o `GalleryView` desktop in-app; o gap era ergonomia. Novo composable `dashboard/composables/useGalleryTouchGestures.js` (pinch para zoom via `onZoom` do `useImageZoom`, swipe horizontal para navegar entre imagens, swipe-down para fechar — bloqueados enquanto o zoom > 1). Wiring mínimo no `GalleryView.vue`: handlers touch no container central (inertes em desktop/mouse) + ajustes **somente responsivos** com breakpoint `sm:` (em telas < 640px: esconde trilhos laterais de navegação, botões de zoom/rotate e nome do arquivo, liberando a largura toda para a imagem). Desktop ≥ 768px renderiza exatamente como antes.
- **Snooze com horário customizado (item 5).** Novo `MobileSnoozeSheet.vue` conectando os MESMOS helpers do desktop (`findSnoozeTime`, `snoozedReopenTime` de `helper/snoozeHelpers.js`, referência `CustomSnoozeModal.vue`): presets "Até a próxima resposta", "Daqui a 1 hora", "Até amanhã", "Até a próxima semana" (com horário de reabertura calculado ao lado) + `<input type="datetime-local">` nativo para data/hora livre. Plugado nos dois pontos que antes fixavam "até a próxima resposta": card Snooze do `MobileConversationActionsView.vue` e opção Adiar do status sheet da lista (`MobileConversationList.vue`), ambos despachando o `toggleStatus` existente com o `snoozedUntil` escolhido. Chaves `MOBILE.SNOOZE.*` em `en`/`pt`/`pt_BR`.

Haptics: presets e confirmar com `v-haptic-tap` + `medium()` síncrono. Itens 4 e 5 do roadmap marcados como entregues.

### 2026-06-11 — Lote A do roadmap: badge no ícone, filtro de inbox, câmera e shortcuts

Primeira leva do plano de execução (`chatwitdocs/mobile-roadmap-execution-plan.md`):

- **Badge de não lidas no ícone do app (item 12).** `components-next/mobile/useAppBadge.js` espelha o getter `notifications/getUnreadCount` em `navigator.setAppBadge`/`clearAppBadge` (iOS 16.4+ PWA instalado, Android/Chrome); montado no `MobileLayout.vue`. Com o app fechado, `public/sw.js` mantém o badge como contagem das notificações ainda na tela (`registration.getNotifications()`) após cada `push`/`notificationclick`.
- **Filtro por inbox na lista (item 6).** `MobileFilterSheet.vue` ganhou a seção Inbox (chips "Todas as caixas" + uma por inbox via `inboxes/getInboxes`, exibida só com 2+ inboxes). `MobileConversationList.vue` propaga `inboxId` em `setChatListFilters`/`updateChatListFilters` (vira `inbox_id` na API, mesmo contrato do desktop) e despacha `setActiveInbox` para o guard de websocket usado pelas views de inbox do desktop. Chaves `MOBILE.FILTER_SHEET.INBOX*` em `en`/`pt`/`pt_BR`.
- **Captura direta de câmera no composer (item 19).** Botão de câmera no `MobileReplyBox.vue` abrindo `<input type="file" accept="image/*" capture="environment">`; o arquivo cai no MESMO `onFileChange` do anexo normal (DirectUpload/FileReader). Chave `MOBILE.CHAT.TAKE_PHOTO`.
- **Atalhos do ícone (item 16).** `manifest.json` ganhou `shortcuts` (Conversas/Inbox → `/?mobile_tab=...`, Android long-press; iOS ignora). `components-next/mobile/mobileDeepLink.js` captura o param no load do módulo (antes dos redirects de boot do router descartarem a query) e `MobileLayout.vue` aplica via `router.replace` na tab correspondente.

Haptics: chips de inbox e botão de câmera com `v-haptic-tap` + haptic síncrono no handler. Desktop intocado — mudanças em `components-next/mobile/`, `locale/*/mobile.json`, e adições puramente aditivas em `public/sw.js`/`public/manifest.json` (push e instalação seguem idênticos).

### 2026-06-11 — Haptics via Trusted-Tap Switch Overlay (patch do iOS 26.5)

A Apple **patcheou no iOS 26.5** o truque do toggle programático: `label.click()` em `<input type="checkbox" switch>` não dispara mais o Taptic Engine ([ios-haptics](https://github.com/tijnjh/ios-haptics) documenta "iOS 17.4 até 26.4"). O haptic do switch agora só dispara quando o **tap real do usuário** aterrissa diretamente no controle (clique trusted). `navigator.vibrate` segue inexistente no Safari 26. Por isso o PWA ficou mudo em aparelhos atualizados, enquanto o app nativo (UIKit) vibra normalmente.

- **Nova diretiva `v-haptic-tap`** (`components-next/mobile/hapticTap.js`): injeta um `<input type="checkbox" switch>` transparente (absolute/inset-0/opacity-0, `aria-hidden`, `tabindex=-1`) dentro do elemento tocável. O tap físico do usuário toggla o switch → haptic do sistema (estilo tap de teclado) → o clique borbulha para o handler normal do botão. No-op onde existe Vibration API (Android). Hosts `disabled` têm o toggle cancelado para não dar feedback tátil em controle morto.
- **`useHaptics.js`**: ao receber um tap trusted no overlay, a diretiva chama `notifyTrustedHapticTap()`; o burst programático do mesmo gesto é suprimido (janela de 400ms) para não duplicar haptic em iOS ≤ 26.4. O caminho programático permanece para iOS 17.4–26.4 e para feedback **dirigido por gesto** (threshold de swipe, pull-to-refresh, drag do pager), onde nenhum tap real atinge um switch — nesses casos, em iOS ≥ 26.5 degrada silenciosamente (limitação da plataforma, sem workaround conhecido).
- **Aplicado em:** tabs do `MobileBottomTabBar`, status cards e todas as linhas de ação do `MobileConversationActionsView` (assignee/team/priority/add label/participants/mute/share), botões de swipe revelados do `MobileSwipeableRow` (cobre listas de conversas e inbox), opções dos sheets (`MobileConversationStatusSheet`, `MobileActionPickerSheet`, `MobileMultiPickerSheet` + botão aplicar) e botão enviar do `MobileReplyBox`.

Desktop intocado: diretiva e usos vivem só em `components-next/mobile/`; `useHaptics.js` é consumido apenas pelo módulo mobile.

### 2026-06-11 — Native List Assembly Animation, Gesture-Synchronous Haptics, Mute & Share

Native-parity pass replicating the official app's loading feel and fixing iOS haptics that never fired on real devices:

- **iOS haptics fired after `await` never reached the Taptic Engine.** Safari requires the hidden-switch toggle (`<input type="checkbox" switch>`, iOS 17.4+) to run inside transient user activation, which expires across a network `await`. Every mobile call site (`toggleStatus` resolve/status flows in `MobileConversationList.vue` and `MobileConversationActionsView.vue`, assignee/team/priority/labels/participants sheets, both send paths in `MobileReplyBox.vue`) now fires the haptic synchronously at tap time, before dispatching. `useHaptics.js` also appends a persistent hidden switch to `document.body` (the proven variant; previously a throwaway element in `document.head`) and reuses it across pulses.
- **List "assembly" animation (native `LinearTransition.springify()` parity).** New `composables/useStaggeredEnter.js` provides batch-relative stagger delays for `<TransitionGroup>` enter hooks. `MobileConversationList.vue` and `MobileInboxView.vue` wrap their rows in `<TransitionGroup appear>` with Tailwind-only classes: staggered fade/slide/scale enter (`cubic-bezier(0.34,1.56,0.64,1)` back-out spring), FLIP `move-class` so rows spring into place on reorder/insert (new message bumps a conversation to the top with a spring, like the native FlashList), and `!absolute` leave so siblings close the gap smoothly when a row is resolved/removed.
- **Mute/unmute + native share (parity gaps from the official app).** New "More actions" section in `MobileConversationActionsView.vue` connecting the existing desktop store actions `muteConversation`/`unmuteConversation` (same `CONTACT_PANEL.*MUTED_SUCCESS` toasts as desktop `MoreActions.vue`) and a conversation link share built from the desktop `conversationUrl`/`frontendURL` helpers — `navigator.share` opens the iOS native share sheet, with `copyTextToClipboard` fallback (`MOBILE.ACTIONS.MORE.*` keys in `en`, `pt`, `pt_BR`).

Desktop remains untouched: changes live in `components-next/mobile/`, the two mobile-only composables, and `locale/*/mobile.json`.

### 2026-06-10 — iOS Haptics via Taptic Engine + Conversation Actions Native Parity

Problem observed in the mobile PWA on iPhone:

- `useHaptics.js` relied exclusively on `navigator.vibrate`, which iOS Safari does not implement — no haptic ever fired on iPhones, including when resolving a conversation.
- The status cards in `MobileConversationActionsView.vue` reused the long list-filter labels (`Pendentes`, `Adiadas`, `Resolvidas`) at 15px inside ~64px-wide cards, causing the text to overflow and clip.
- Section headers and card radii diverged from the native Chatwoot iOS app (oversized `text-lg` headers, extra "Configurações" heading above the first card group).

Implemented:

- `composables/useHaptics.js` now falls back to the only web path into the Taptic Engine on iOS (17.4+): toggling a hidden native `<input type="checkbox" switch>` via `label.click()` inside the user gesture, the same approach as the `ios-haptics` package. Android/Chromium keeps the Vibration API. New API mirrors UIKit generators: `light`/`medium`/`heavy` (impact), `selection`, `success`/`error` (notification, emulated with pulse bursts on iOS).
- Resolving a conversation now fires the `success` notification haptic (double pulse) both in `MobileConversationActionsView.vue` and in the status sheet flow of `MobileConversationList.vue`; other status changes keep `medium`.
- Status cards redesigned for native parity: dedicated short action labels (`MOBILE.ACTIONS.STATUS.OPEN/PENDING/SNOOZE/RESOLVE` — pt_BR `Aberta/Pendente/Adiar/Resolver`), 13px `leading-tight break-words` typography that can no longer overflow, `rounded-2xl` radius, tighter padding, springier `active:scale-[0.96]` press.
- Section headers reduced to small gray labels (13px) and the redundant heading above the assignee/team/priority card removed, matching the native app layout. Priority empty state now uses `MOBILE.ACTIONS.PRIORITY.NONE` ("No Priority Added" / "Sem prioridade").
- `MobileLayout.vue` root now sets `-webkit-tap-highlight-color: transparent` (inherited), removing Safari's gray tap flash across the whole mobile module for a native feel.

Desktop remains untouched; all changes live in `components-next/mobile/`, `composables/useHaptics.js` (mobile-only consumer) and `locale/en|pt_BR/mobile.json`.

### 2026-05-06 — Mobile Conversation List and Audio Playback Fix

Problem observed in the mobile PWA:

- `MobileConversationList.vue` reused the desktop `ConversationCard.vue` but did not provide the required `currentContact` prop, causing `TypeError: Cannot read properties of undefined (reading 'name')` and leaving the conversation list blank.
- The shared `AudioChip.vue` player relied on a hidden `<audio>` element and did not await `audio.play()`, so mobile/PWA playback failures could leave the UI cycling speed labels (`1x`, `1.5x`, `2x`) without actual audio.
- Incoming WhatsApp/Evolution Go voice notes are stored as OGG/Opus, which Chrome can play but iOS Safari/PWA does not support. Chatwit-recorded audio is MP3 and was already compatible.
- `timeStampAppendedURL()` only accepted absolute URLs, while Active Storage can provide relative `/rails/active_storage/...` paths.

Implemented:

- `MobileConversationList.vue` now connects the same desktop-backed contact, assignee, and inbox store data into `ConversationCard.vue`, including inbox preload for card metadata.
- `AudioChip.vue` now keeps the media element visually hidden without `display: none`, reloads unloaded media before playing, applies playback speed before `play()`, forces the element back to audible output when the local mute button is off, awaits the play promise, syncs UI state from native `play/pause/error` events, and swaps to native browser controls as a fallback when playback fails.
- OGG/Opus audio attachments now expose a same-account `playback_url` that lazily transcodes the original file to MP3 with ffmpeg, caches it in `playback_file`, and redirects the player to the compatible Active Storage blob. The original OGG remains available for download.
- `timeStampAppendedURL()` now supports relative URLs while preserving invalid absolute URL validation.
- Production storage remains MinIO/S3-compatible when `ACTIVE_STORAGE_SERVICE=s3_compatible` is set by the stack; the audio playback fix is in the browser player path and the authenticated attachment playback endpoint. The Rails runtime image now includes `ffmpeg` for this conversion.

Desktop conversation behavior remains unchanged; the list fix is isolated to `components-next/mobile/`, and the audio change hardens the shared message player used by both desktop and mobile.

### 2026-05-02 — WhatsApp Interactive Template Conversation Context

Implemented in the mobile reply box only:

- Passed the existing `currentChat.id` into the shared WhatsApp templates modal as `conversationId`.
- This keeps the mobile path connected to the same desktop dispatch endpoint for saved interactive messages, instead of creating mobile-only send logic.

Result:

- Saved WhatsApp interactive messages shown in the shared templates picker can be sent from mobile conversation view without hitting the "open a conversation" guard.
- Desktop behavior remains unchanged.

### 2026-04-22 — InfinitePay Push-Only Toggle no Mobile Settings

Implemented in the mobile settings shell only:

- Added the existing account-level `infinitepay_push_only` control to `components-next/mobile/MobileSettingsView.vue`.
- Reused the same `useAccount().updateAccount()` flow and the same InfinitePay i18n copy already used in desktop account settings.
- Kept the change isolated to the mobile settings notifications section so desktop behavior and existing account settings screens remain unchanged.

Result:

- Mobile PWA users can now enable or disable the "Push PWA exclusivo para confirmações de pagamento" option directly from the mobile settings screen.
- The mobile layer continues to connect existing desktop-backed account settings instead of introducing parallel business logic.

### 2026-03-26 — Mobile Pull-To-Refresh Petal Loader

Implemented in the mobile inbox shell only:

- Replaced the old pull-to-refresh arrow in `components-next/mobile/MobilePullToRefresh.vue` with a dedicated petal loader that progressively fills as the downward swipe advances.
- Switched the refreshing state to the Chatwit petal asset in `public/loading-petulas.svg`, keeping all petals filled while the refresh stays active.
- Tightened gesture detection so pull-to-refresh only arms when the mobile list is actually at the top and the gesture is vertical, reducing accidental triggers during normal scrolling and row swipes.
- Kept the existing notifications fetch flow intact by reusing the same mobile inbox refresh action and haptic threshold feedback.
- Refined the pull motion so the inbox content is translated instead of being pushed down by a temporary spacer, which removes the visible jump during drag/release.
- Delayed the arm state so the petals only fully fill, vibrate, and start spinning after a deliberate pull; fast flicks no longer trigger refresh as easily.
- Suppressed the duplicate inbox loading spinner during pull refresh and preserved the current list while re-fetching, avoiding the double-loader state in mobile.

Desktop behavior remains unchanged because the change is isolated to `components-next/mobile/` and the dedicated mobile inbox list wrapper.

### 2026-03-16 — Mobile Web Push Duplicate Guard

Problem observed in the mobile PWA flow:

- after uninstalling and reinstalling the Chatwit PWA, a browser could end up with a new Web Push subscription while an older backend record still existed for the same user
- disabling push only unsubscribed locally and did not remove the stored `browser_push` endpoint on the server
- duplicate push deliveries could therefore render the same notification twice on the same mobile device

Implemented in the shared push flow used by mobile settings and desktop settings:

- added backend deletion for browser push subscriptions by `endpoint` in `Api::V1::NotificationSubscriptionsController`
- updated `pushHelper.js` so unsubscribe removes the current `browser_push` registration from the backend and then unsubscribes the browser
- added a duplicate guard in `public/sw.js` based on recent notification identity (`tag`, title, body, URL) and disabled `renotify` for same-tag replacements

Desktop behavior remains unchanged because the business flow is still the same shared Web Push stack; the change only cleans up stale subscriptions and suppresses duplicate rendering on the client.

### 2026-03-16 — Mobile Push Vibration Pattern

Implemented in the shared PWA service worker used by the mobile shell:

- kept push vibration inside `public/sw.js`, where Web Push notifications are rendered
- upgraded the default vibration pattern to a more noticeable sequence for supported devices
- allowed the push payload to provide a custom `vibrate` array in the future without changing the client again

Desktop behavior remains unchanged because this only affects OS-level push presentation on devices that support notification vibration.

### 2026-03-15 — Mobile Haptic Feedback Refinement

Implemented in the mobile shell only:

- Added a one-shot light haptic when the conversation pager completes opening the second actions screen in `components-next/mobile/MobileChatView.vue`.
- Added success haptics after successful sends in `components-next/mobile/MobileReplyBox.vue`, including WhatsApp template sends that already use the existing desktop-backed send flow.
- Added discrete confirmation haptics for successful status, assignee, team, priority, label, and participant updates in `components-next/mobile/MobileConversationActionsView.vue`.
- Reused the existing `composables/useHaptics.js` wrapper and kept all business logic on the same desktop stores/actions already used by the mobile layer.

Desktop behavior remains unchanged because the refinement is isolated to mobile components and existing mobile composables.

### 2026-03-14 — Mobile Conversation Pager Width Fix

The mobile conversation pager could size each horizontal page against the full `200%` track width instead of a single viewport. In practice this pushed the chat surface sideways and made message bubbles appear cut off.

Implemented in the mobile shell only:

- Reworked the pager track in `components-next/mobile/MobileChatView.vue` so each page is a single viewport-wide flex item.
- Added explicit shrink/width guards to the message page container used by the reused desktop `MessagesView`.
- Preserved the existing desktop message components and store flow unchanged.

Desktop behavior remains unchanged because the fix is isolated to the dedicated mobile pager layout.

### 2026-03-14 — Mobile Chat Bubble Width Clamp

The mobile conversation view could clip wide message bubbles, especially WhatsApp interactive cards and other rich payloads that inherited desktop-oriented width envelopes.

Implemented in the mobile shell only:

- Added a mobile-only bubble width clamp in `components-next/mobile/MobileChatView.vue` based on the native Chatwoot app proportion (`300px` max width with viewport fallback).
- Forced rich/interactive bubble internals to respect the mobile bubble width instead of expanding past the viewport.
- Added safer word wrapping for long content inside mobile message bubbles.

Desktop behavior remains unchanged because the fix is isolated under `.mobile-chat-messages` in the dedicated mobile layout.

### 2026-03-14 — Mobile Settings Alinhado ao Fork Chatwit

#### Decisão de produto

- A documentação do módulo mobile passou a deixar explícito, logo no topo, que o PWA do Chatwit não deve portar suporte, widgets, branding ou fluxos específicos do app nativo oficial do Chatwoot.
- O app nativo segue sendo apenas referência visual; funcionalidades sem contraparte real no fork Chatwit continuam fora de escopo.

#### Ajustes implementados

- A tela `MobileSettingsView.vue` agora conecta o seletor de idioma ao fluxo real de `ui_settings.locale` já usado no web.
- A troca de conta passou a usar a mesma estratégia segura do desktop: navegação para `/app/accounts/:id/dashboard`.
- As labels mobile receberam as novas chaves de idioma necessárias em `en`, `pt` e `pt_BR`.

### 2026-03-14 — Mobile Shell Isolation Fix

#### Problem

- On small screens, the dashboard could briefly evaluate desktop shell state before fully settling into `MobileLayout`.
- That short-lived desktop path was enough to emit `SIDEBAR.CONVERSATION_WORKFLOW` warnings in `pt_BR` and to load desktop-only command bar code, which also produced the `Lit is in dev mode` console warning in mobile sessions.
- Mobile swipe rows also used `aria-hidden` on a container that still held focusable action buttons, triggering accessibility warnings in the browser console.

#### Fix

- Stabilized the initial viewport detection in `Dashboard.vue` with `window.innerWidth` as the initial width passed into `useWindowSize()`.
- Added the missing `SIDEBAR.CONVERSATION_WORKFLOW` key to Portuguese sidebar locale bundles.
- Reworked `MobileSwipeableRow.vue` so hidden swipe actions become inert and leave the tab order instead of being hidden with focused descendants.

#### Validation result

- The mobile shell remains isolated from desktop navigation setup on first render.
- Portuguese mobile sessions no longer emit the `SIDEBAR.CONVERSATION_WORKFLOW` warning.
- Swipe action rows no longer reproduce the `Blocked aria-hidden on an element because its descendant retained focus` warning.

### 2026-03-14 — Native Conversation Actions Screen

#### Problem

- The mobile conversation screen still lacked the native Chatwoot app's second horizontal page for conversation actions.
- Users could not swipe left inside an open chat to reveal the dedicated actions/details screen shown in the native app reference.
- Existing functionality for assignee, team, priority, labels, participants, and conversation attributes was available, but not surfaced in the native mobile layout.

#### Fix

- Reworked `MobileChatView.vue` into a two-page horizontal pager: chat on the first page and conversation actions on the second.
- Added `MobileConversationActionsView.vue` with native-style status cards, settings card, labels section, participants section, and attributes section.
- Added mobile-only picker sheets for assignee/team/priority selection and multi-select sheets for labels and participants.
- Updated `MobileChatHeader.vue` with native-style action buttons that open the actions page from the header.

#### Validation target

- In a mobile conversation, swiping from right to left reveals the conversation actions page without leaving the current route.
- The second page follows the native Chatwoot structure: top status cards, settings card, labels, participants, and attributes.
- Changing assignee, team, priority, labels, participants, or status continues to use the existing Chatwit/Desktop data flow.

### 2026-03-14 — Gesture Polish for Conversation Pager

#### Problem

- The two-page conversation pager was functionally correct, but the transition still felt web-like.
- Closing the actions page with the inverse swipe lacked enough visual weight and snap feedback.

#### Fix

- Added drag-progress-driven depth to the chat page with scale, radius, and shadow changes during horizontal movement.
- Added parallax and staged opacity for the actions page while it enters and exits.
- Added threshold haptic feedback and touch-cancel cleanup so the swipe open/close interaction feels more native.
- Added a subtle in-context swipe hint pill on the chat page.

#### Validation target

- Swiping left opens the actions page with progressive depth/parallax instead of a flat page slide.
- Swiping right on the actions page closes it with the same snap behavior and without gesture residue.

### 2026-03-13 — Mobile Composer Popout Height Fix

#### Problem

- In mobile viewport, tapping the maximize button in the conversation composer opened the popout reply box with desktop-sized minimum heights.
- The expanded composer could grow past the viewport height, pushing the top of the reply box off-screen instead of keeping the editor scrollable.

#### Fix

- Added a mobile-only override in `MessagesView.vue` for the popout composer (`.modal-mask`).
- On screens below `768px`, the popout reply box now anchors near the bottom, uses full mobile width with safe margins, and caps its total height to the viewport.
- The inner ProseMirror editor now gets a mobile-specific max height, so long content scrolls inside the editor instead of stretching the whole composer.

#### Validation result

- Reproduced in MCP Playwright mobile mode at `336x498`.
- After opening the composer popout and inserting many lines, the expanded reply box remained inside the viewport and the editor switched to internal scrolling (`clientHeight: 256`, `scrollHeight: 758`).

### 2026-03-13 — Mobile Reply Toggle Fix

#### Problem

- In mobile conversation view, the `Responder / Mensagem Privada` switch could become stuck in private-note mode.
- The root cause was not the switch itself: on first render, the reply box sometimes received an empty `inbox`, so `inboxMixin` failed to detect WhatsApp conversations and incorrectly marked the thread as reply-restricted.
- The private-note label could also wrap vertically inside the segmented control on small screens.

#### Fix

- Added a channel-type fallback in `inboxMixin.js` using the selected conversation metadata when `inbox.channel_type` is not available yet.
- This restores correct WhatsApp detection during mobile conversation boot, so the reply-mode switch stays enabled when template-based WhatsApp replies are allowed.
- Tightened the `EditorModeToggle.vue` label styling for mobile with nowrap and smaller spacing/text sizing so the segmented control stays on a single line.

#### Validation result

- Reproduced and validated in MCP Playwright mobile mode at `336x498`.
- The switch now renders as enabled, the private-note label stays on one line (`16px` label height inside a `32px` control), and clicking from `NOTE` returns the composer to `REPLY` successfully.

### 2026-03-13 — Mobile Stabilization Pass

After the initial mobile implementation, a stabilization pass was required because the mobile dashboard was functional but not production-safe in real `pt` and `pt_BR` usage.

#### Why this was necessary

- The mobile shell was emitting repeated `MOBILE.*` i18n warnings for Portuguese users because the mobile translation bundle existed only in English.
- Notification-driven mobile navigation could fail when the payload arrived without a complete `primaryActor` reference.
- `InboxCard` assumed sender metadata was always present, which is not true for every notification payload.
- `MobileConversationList.vue` was initially wired to non-existent Vuex paths (`chatList/*`) instead of the real conversation store API, which caused runtime errors in mobile.
- `MobileLayout.vue` kept hidden tabs mounted with `v-show`, so inactive mobile views could still react to state changes and crash the current screen.

#### What was changed

| File | What changed | Why |
|------|--------------|-----|
| `i18n/locale/pt/mobile.json` | Added Portuguese mobile translations | Removes missing-key warnings for `pt` users |
| `i18n/locale/pt_BR/mobile.json` | Added Brazilian Portuguese mobile translations | Removes missing-key warnings for `pt_BR` users |
| `i18n/locale/pt/index.js` | Registered `mobile.json` bundle | Makes the new mobile keys available in runtime |
| `i18n/locale/pt_BR/index.js` | Registered `mobile.json` bundle | Makes the new mobile keys available in runtime |
| `components-next/Inbox/InboxCard.vue` | Added guards for missing sender name/thumbnail | Prevents render failures when notification metadata is incomplete |
| `components-next/mobile/MobileInboxView.vue` | Guarded conversation open flow when `primaryActor.id` is absent | Prevents broken navigation from malformed/incomplete notification payloads |
| `routes/dashboard/inbox/InboxList.vue` | Guarded inbox navigation against missing `primaryActor`/`inboxId` | Keeps desktop/inbox behavior consistent with the mobile fix |
| `components-next/mobile/MobileConversationList.vue` | Rewired to real store getters/actions (`getChatListLoadingStatus`, `conversationPage/*`, `setChatListFilters`, `emptyAllConversations`) | Fixes runtime errors caused by invalid Vuex integration |
| `components-next/mobile/MobileLayout.vue` | Switched tab rendering from `v-show` to `v-if`/`v-else-if` | Ensures only the active mobile tab is mounted, reducing hidden-view crashes |

#### Validation result

- Mobile translation warnings for `MOBILE.*` were eliminated in MCP Playwright mobile mode.
- The `TypeError` and invalid Vuex action errors observed during mobile navigation no longer reproduced after the store/layout fixes.
- The mobile dashboard could be opened again in mobile mode without the previous render-loop failures.

#### Remaining issues outside the mobile shell

- `mini-profiler-resources/includes.js` still returns `500` in this dev environment.
- Some Active Storage image URLs still return `404`/`500`.

These remaining errors are backend or asset-serving issues, not mobile layout/runtime issues.

### 2026-03-13 — Phase 2: Enhanced Mobile UX

#### New Components
| Component | Path | Description |
|-----------|------|-------------|
| `MobileSwipeableRow.vue` | `components-next/mobile/MobileSwipeableRow.vue` | Reusable swipe-to-reveal actions wrapper for list rows. Supports configurable action buttons, threshold-based activation, horizontal/vertical conflict resolution, and auto-close via provide/inject. |

### 2026-03-13 — Mobile Conversation Status Sheet

#### Problem

- In mobile conversation list, swipe actions existed, but the status-change flow from the native/mobile app was missing.
- The user needed the same interaction shown in the reference images: swipe left, tap `Status`, then choose between `Pendentes`, `Adiadas`, and `Resolvidas` in a bottom sheet.

#### Fix

- Replaced the direct swipe actions on mobile conversation rows with a single `Status` action.
- Added `MobileConversationStatusSheet.vue` to render the bottom sheet with the three status options.
- Wired the mobile flow to the existing conversation status update pipeline:
    - `Pendentes` -> `pending`
    - `Adiadas` -> `snoozed` using the existing `until_next_reply` behavior
    - `Resolvidas` -> `resolved`, including the existing required-attributes validation modal when needed

#### Validation target

- Swiping a conversation to the left now reveals only the `Status` action in mobile mode.
- Tapping `Status` opens a bottom sheet consistent with the provided images.
- Selecting a status uses the same underlying store/action flow already used by the regular app.

#### New Composables
| Composable | Path | Description |
|------------|------|-------------|
| `useHaptics.js` | `composables/useHaptics.js` | Vibration API wrapper with `light()`, `medium()`, `heavy()`, `success()` methods. Graceful no-op when API unavailable. |
| `useSwipeBack.js` | `composables/useSwipeBack.js` | Edge-swipe gesture detection composable. Activates on touch within 20px of left edge (right edge in RTL). Returns reactive `swipeOffset` for visual feedback. Threshold: 100px to trigger navigation. |
| `useKeyboardResize.js` | `composables/useKeyboardResize.js` | Virtual keyboard detection via `visualViewport` API. Returns `keyboardHeight` and `isKeyboardOpen` reactive refs. Auto-scrolls focused input into view. |

#### Modified Components
| Component | Path | Changes |
|-----------|------|---------|
| `MobileConversationList.vue` | `components-next/mobile/MobileConversationList.vue` | Wrapped `ConversationCard` in `MobileSwipeableRow` with Resolve/Reopen and Delete swipe actions. Added provide/inject for single-open-row management. Haptic feedback on swipe threshold. |
| `MobileInboxView.vue` | `components-next/mobile/MobileInboxView.vue` | Wrapped `InboxCard` in `MobileSwipeableRow` with Mark Read and Delete swipe actions. Added provide/inject for single-open-row management. Haptic feedback on actions. |
| `MobileChatView.vue` | `components-next/mobile/MobileChatView.vue` | Integrated `useSwipeBack` for edge-swipe-right back navigation with visual slide effect. Integrated `useKeyboardResize` to adjust padding when virtual keyboard opens, keeping reply box visible. |
| `MobileBottomTabBar.vue` | `components-next/mobile/MobileBottomTabBar.vue` | Added haptic feedback (`light()`) on tab switches via `useHaptics`. |
| `MobilePullToRefresh.vue` | `components-next/mobile/MobilePullToRefresh.vue` | Added haptic feedback (`medium()`) when pull distance crosses the refresh threshold. Fires once per gesture via flag. |

#### i18n
| File | Changes |
|------|---------|
| `i18n/locale/en/mobile.json` | Added `MOBILE.SWIPE` keys: `RESOLVE`, `REOPEN`, `DELETE`, `MARK_READ`, `CONFIRM_DELETE` |

#### Functionalities Added
- **Swipe actions**: Swipe left on conversation rows to reveal Resolve/Reopen and Delete buttons; swipe left on notification rows to reveal Mark Read and Delete buttons
- **Haptic feedback**: Vibration API triggers on tab switch, swipe action threshold, pull-to-refresh threshold, and back gesture completion
- **Gesture navigation**: Swipe right from the left screen edge in chat view to navigate back to the list (with RTL support)
- **Keyboard handling**: Chat view auto-adjusts layout when the virtual keyboard opens, preventing the reply box from being hidden behind the keyboard
