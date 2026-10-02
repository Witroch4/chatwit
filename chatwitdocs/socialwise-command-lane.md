# Faixa de comando do Socialwise (`/palavra`)

Mensagem **recebida**, de texto, sem anexo, não privada, que não é clique de botão/lista/quick
reply/postback e que começa com `/palavra` (`\A/[a-z][a-z0-9-]*(\s|\z)`, sem diferenciar
maiúsculas), numa caixa com o hook `socialwise_flow`, vai direto ao webhook do Socialwise com
`metadata.command_lane: true`.

- Código: `lib/integrations/socialwise_flow/command_lane.rb` (`CommandLane.eligible?`) e o bloco
  no topo de `ProcessorService#perform` (`forward_command_lane`).
- **Pula** `should_run_processor?`, o ownership guard, o handoff, o debounce e o indicador de
  digitação. Funciona inclusive em conversa entregue a humano.
- **Não altera** a conversa (`additional_attributes`, status).
- **Não usa** `get_response`: ele checa `publish_allowed?` antes do POST. A faixa reusa o mesmo
  `build_request_payload` do fluxo normal (session_id = `contact_inbox.source_id`, ids de conta,
  caixa, conversa, `display_id`, mensagem) e só acrescenta a flag. Nunca loga o payload.
- **Clique nunca é comando**: `button_reply`, `list_reply`, `quick_reply_payload` e
  `postback_payload` ficam fora da faixa mesmo com título `/...` e seguem o caminho normal (que
  respeita o handoff). O Socialwise também descarta clique na faixa.
- O Socialwise responde `{"status": "accepted", "async": true}` e, se for o caso, fala pela API
  do Agent Bot. Para quem não é autorizado, silêncio. Ele não confia em
  `chatwit_base_url`/`chatwit_agent_bot_token` do payload para esta faixa: usa a config própria e
  confere o remetente consultando a conversa (`GET /api/v1/accounts/:account_id/conversations/:display_id`)
  com o token do Platform Bot.
- Toda a regra (quais comandos existem, quem pode usar) mora no FastAPI:
  `witdev-platform-core/backend/domains/socialwise/services/om_access/`. O padrão `/palavra` é o
  mesmo de `commands.py` (`COMMAND_RE`); se um mudar, o outro muda junto.

Primeiro uso: `/om-windows <nome>` e `/om-linux <nome>` (bot de acesso OmniRoute, 2026-09-24).
