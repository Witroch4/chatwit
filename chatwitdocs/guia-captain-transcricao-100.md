# Guia — Captain + Transcrição de Áudio 100% ponta a ponta

> Consolidação do diagnóstico de 2026-07-02 (produção lida via Portainer/console) +
> teste empírico de áudio documentado em
> `witdev-platform-core/docs/agent-memory/witdev-audio-transcription.md`.
> Conta de referência em produção: **3 (DraAmandaSousa)** — a conta 6 não existe.

## Estado verificado em produção (2026-07-02)

| Item | Estado | Veredito |
|---|---|---|
| `INSTALLATION_PRICING_PLAN` | `enterprise`, locked | ✅ saudável — reconcile não arranca features premium |
| Feature `captain_integration` + `captain_integration_v2` (conta 3) | ligadas | ✅ |
| Cota Captain (`CAPTAIN_CLOUD_PLAN_LIMITS` vazio) | 99.884 disponíveis / 116 usadas | ✅ ilimitado na prática |
| Toggle `audio_transcriptions` (conta 3) | `nil` | ❌ **gate que barra a transcrição hoje** |
| `CAPTAIN_LLM_ROUTE` | `witdev` | ⚠️ configurada… |
| `CAPTAIN_WITDEV_PROXY_API_KEY` | **vazia** | ❌ …mas incompleta → rota witdev silenciosamente desativada |
| Rota efetiva do Captain | legado (`gemini-2.5-flash-lite` via `CAPTAIN_GEMINI_API_KEY`) | ⚠️ não é o que o Super Admin aparenta |
| `CAPTAIN_OPEN_AI_API_KEY` | preenchida, **não é chave OpenAI** (`sk-…`) | ❌ Whisper/embeddings/Files API vão dar 401 |
| `CAPTAIN_OPEN_AI_ENDPOINT` | vazio (→ `api.openai.com`) | ok |

O cadeado amarelo no Super Admin = feature `premium: true` do `config/features.yml`.
Verde + cadeado significa **ligada**. Não é bloqueio.

## Checklist para ficar 100%

### 1. Ligar a transcrição da conta (2 min, sem deploy)

App → **Configurações da Conta → Configurações Gerais → "Transcrição de Áudio" → ON**
(o card só aparece porque o Captain está habilitado na conta). Ou via console:

```bash
ssh -i ~/.ssh/keys/production-server.key root@49.13.155.94 \
  "docker exec \$(docker ps -qf name=chatwoot_app_chatwoot_app | head -1) \
   bundle exec rails runner \"Account.find(3).update!(audio_transcriptions: true)\""
```

### 2. Completar a rota WitDev do Captain (5 min, precisa restart)

Super Admin → Settings → Captain:
- **WitDev Proxy API Key** → colar a `LITELLM_PROXY_API_KEY` (a mesma do `.env` da
  plataforma). É o único campo faltando — sem ele o Captain cai no legado sem avisar.
- **WitDev Model**: `witdev_antigravity/gemini-3.5-flash-low` funciona para chat.
  Se quiser Claude no atendimento: `witdev_claude/opus` ou `witdev_claude/sonnet`.
- **Reiniciar o serviço** (`chatwoot_app_chatwoot_app` + sidekiq) — a rota e o registro
  de aliases acontecem no boot.

### 3. Resolver a transcrição de verdade (escolher UMA via)

**Via A — corrigir a chave OpenAI (zero código):** colar uma chave OpenAI real
(`sk-…`) em **OpenAI API Key** no Super Admin → Captain. O Whisper (`whisper-1`,
hardcoded em `enterprise/app/services/messages/audio_transcription_service.rb`) volta a
funcionar, e de quebra conserta **embeddings** (ingestão de documentos do Captain) e a
**Files API** (PDF → FAQ), que usam a mesma chave e hoje estão quebrados igual.

**Via B — rotear transcrição pelo proxy WitDev (mudança de código no Chatwit):**
adaptar o `AudioTranscriptionService` para, quando `CAPTAIN_LLM_ROUTE=witdev`, mandar o
áudio como `input_audio` (OpenAI chat completions) ao LiteLLM com alias configurável
(sugestão: `CAPTAIN_WITDEV_TRANSCRIPTION_MODEL`, default
`witdev_antigravity/gemini-3.1-pro-low` — o campeão do teste jurídico). Vantagens:
sem dependência de chave OpenAI para áudio, precisão maior no PT-BR regional.
**Atenção:** embeddings/Files API continuariam precisando da chave OpenAI de qualquer
forma — ou seja, a Via A é necessária de todo jeito se o Captain usa documentos/PDF.

**Recomendação: fazer a Via A já (destrava tudo) e a Via B como melhoria em seguida.**

### 4. Regras de ouro para áudio via proxy (do teste empírico)

- ✅ `witdev_antigravity/gemini-3.1-pro-low` — jurídico/precisão (testado)
- ✅ `witdev_antigravity/gemini-3.5-flash-medium` — triagem rápida (testado)
- ❌ `witdev_copilot/*` — **200 OK com transcrição 100% alucinada** (descarta o áudio)
- ❌ `witdev/*` (codex) — HTTP 400, rota não tem `input_audio`
- ❌ `witdev_gemini/*` — 404 sem credencial ativa (estado 2026-07-02)
- Claude (qualquer rota, inclusive Opus) **não tem entrada de áudio** — modelos Claude
  são texto/imagem/PDF. Áudio sempre precisa de um passo speech-to-text antes
  (Whisper ou Gemini nativo).
- 200 OK ≠ transcrição real: validar alias novo com amostra conhecida.

### 5. Melhorias de código pendentes no Chatwit

> **Status 2026-07-02:** itens 1, 2 e 4 **IMPLEMENTADOS** no commit
> `feat(captain): Captain Whisper — dossier transcription via WitDev LLM proxy`
> (`7f48f35d32`, branch develop). Doc: `chatwitdocs/captain-witdev-llm-proxy.md`.

1. ✅ **Erros distintos por gate** em `audio_transcription_service.rb` — agora retorna
   "Captain feature disabled for this account" / "Audio transcription disabled in
   account settings" / "Captain responses quota exhausted".
2. ✅ **Via B implementada como "Captain Whisper"** — `Chatwit::AudioTranscriptionService`
   + config `CAPTAIN_WITDEV_TRANSCRIPTION_MODEL` (default
   `witdev_antigravity/gemini-3.1-pro-low`), select no Super Admin filtrado por
   allowlist de áudio (`witdev_antigravity/*`, `gemini-*`) e recusa em runtime de
   copilot/codex. É o fluxo canônico do dossiê; ativa com a Proxy API Key preenchida
   (independe de `CAPTAIN_LLM_ROUTE`), Whisper legado vira fallback.
3. ⏳ Atualizar **Captain Model legado** (`gemini-2.5-flash-lite` → família 3.x) — é
   escolha de valor no dropdown do Super Admin (config de prod), não mudança de código.
4. ✅ **Aviso de rota incompleta no Super Admin** — banner amarelo na tela do Captain
   quando `CAPTAIN_LLM_ROUTE=witdev` com campos faltando, listando exatamente o que
   falta (Model e/ou Proxy API Key).

Deploy padrão após qualquer mudança: commit → push → `./build.sh --skip-evolution` →
deploy prod.

### 6. Validação final ponta a ponta (depois dos passos 1–3)

1. Enviar/receber um áudio de WhatsApp na conta 3.
2. Baixar o dossiê da conversa → `transcricoes-audio.txt` deve vir preenchido.
3. Conferir no Super Admin (conta 3 → custom attributes) o incremento de
   `captain_responses_usage`.
4. Testar uma resposta do Captain e conferir no log do LiteLLM que o modelo usado é o
   alias witdev (e não gemini-2.5-flash-lite legado).

Notas:
- **Áudios antigos não precisam de reprocessamento** — a transcrição do dossiê é
  on-demand (`transcribe_audio` só chama a API se `meta.transcribed_text` estiver
  vazio); basta baixar o dossiê de novo depois dos passos 1–3 que os áudios antigos
  são transcritos na hora (e ficam cacheados no attachment).
- A transcrição consome cota Captain (`captain_responses_usage` incrementa a cada
  áudio novo). Com `CAPTAIN_CLOUD_PLAN_LIMITS` vazio a cota é ilimitada — se um dia
  esse config for preenchido, contas sem `plan_name` caem para cota **zero**.

## Higiene de credenciais (opcional, recomendado)

Durante o diagnóstico o token de API do Portainer (que fica em `~/.claude.json`, args
do MCP) acabou impresso num transcript local de sessão. Risco baixo (máquina local),
mas se quiser zerar: Portainer → My account → Access tokens → revogar e gerar novo,
atualizando o `-token` no `mcpServers.portainer` do `~/.claude.json`.
