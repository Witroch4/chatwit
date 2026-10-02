# Faixa de comando do Socialwise (`/om-windows`, `/om-linux`)

Mensagem **recebida**, de texto, sem anexo, não privada, que não é clique de botão/lista/quick
reply/postback e cuja primeira linha (depois de tirar o espaço inicial) começa com um comando
**conhecido** — `\A/(om-windows|om-linux)(\s|\z)`, sem diferenciar maiúsculas —, numa caixa com
o hook `socialwise_flow`, vai direto ao webhook do Socialwise com `metadata.command_lane: true`.

**Só comandos conhecidos.** O Socialwise assume *toda* mensagem marcada com `command_lane` e
responde silêncio para quem não é operador. Por isso qualquer outro `/palavra` (`/start`,
`/om-mac`, comando na segunda linha) **não** entra na faixa e segue o fluxo normal, intacto
(com handoff, debounce etc.). A lista mora em `CommandLane::COMMANDS` e espelha `COMMANDS` de
`witdev-platform-core/backend/domains/socialwise/services/om_access/commands.py`: comando novo
lá exige entrada nova aqui.

- Código: `lib/integrations/socialwise_flow/command_lane.rb` (`CommandLane.eligible?`) e o bloco
  no topo de `ProcessorService#perform` (`forward_command_lane`).
- **Pula** `should_run_processor?`, o ownership guard, o handoff, o debounce e o indicador de
  digitação. Funciona inclusive em conversa entregue a humano.
- **Não altera** a conversa (`additional_attributes`, status).
- **Não usa** `get_response`: ele checa `publish_allowed?` antes do POST. A faixa reusa o mesmo
  `build_request_payload` do fluxo normal (session_id = `contact_inbox.source_id`, ids de conta,
  caixa, conversa, `display_id`, mensagem) e só acrescenta a flag. Nunca loga o payload.
- POST com timeout de **10s** (`CommandLane::FORWARD_TIMEOUT_SECONDS`; o Socialwise responde
  `accepted` na hora e roda o comando em background) e **fail-quiet**: erro vira log, não sobe ao job.
- **Clique nunca é comando**: `button_reply`, `list_reply`, `quick_reply_payload` e
  `postback_payload` ficam fora da faixa mesmo com título `/...` e seguem o caminho normal (que
  respeita o handoff). O Socialwise também descarta clique na faixa.
- O Socialwise responde `{"status": "accepted", "async": true}` e, se for o caso, fala pela API
  do Agent Bot. Para quem não é autorizado, silêncio. Ele não confia em
  `chatwit_base_url`/`chatwit_agent_bot_token` do payload para esta faixa: usa a config própria e
  confere o remetente consultando a conversa (`GET /api/v1/accounts/:account_id/conversations/:display_id`)
  com o token do Platform Bot.
- A regra de quem pode usar e a validação do comando moram no FastAPI:
  `witdev-platform-core/backend/domains/socialwise/services/om_access/`.

Primeiro uso: `/om-windows <nome>` e `/om-linux <nome>` (bot de acesso OmniRoute, 2026-09-24).
