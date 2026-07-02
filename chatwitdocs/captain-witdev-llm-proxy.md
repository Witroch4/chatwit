# Captain — Rota WitDev LLM Proxy

## O que é

O Captain passa a ter **duas rotas de LLM**, escolhidas no Super Admin (Settings → Captain → **LLM Route**):

| Rota | Como funciona |
|------|---------------|
| **Chatwoot (legacy)** | Caminho oficial do Chatwoot, intocado: OpenAI API Key / Gemini API Key + `CAPTAIN_OPEN_AI_MODEL`. |
| **WitDev LLM Proxy** | Todas as chamadas de *chat* do Captain vão para o **LiteLLM proxy da plataforma** (`platform-litellm`) via rede Docker compartilhada, usando o **alias canônico** do catálogo da plataforma (ex.: `witdev_claude/sonnet`). |

Segue o contrato da plataforma (`witdev-platform-core/docs/agent-memory/llm-model-catalog-contract.md`):
o catálogo de modelos é listado por `platform-api /api/v1/llm/models` (nunca o LiteLLM direto pelo browser),
o app persiste apenas o alias canônico, e o LiteLLM resolve o provider real.

## Configuração (Super Admin → Settings → Captain)

| Config | Descrição | Padrão |
|--------|-----------|--------|
| `CAPTAIN_LLM_ROUTE` | `chatwoot` (legado) ou `witdev` | `chatwoot` |
| `CAPTAIN_WITDEV_MODEL` | Alias canônico do catálogo. O campo vira um **select carregado ao vivo** do catálogo central; se a plataforma estiver inacessível, vira campo texto (fallback manual). | — |
| `CAPTAIN_WITDEV_PROXY_API_KEY` | API key do LiteLLM proxy (obrigatória na rota witdev) | — |
| `CAPTAIN_WITDEV_PROXY_URL` | Base URL do proxy | `http://platform-litellm:4000` |
| `CAPTAIN_WITDEV_CATALOG_URL` | Endpoint do catálogo | `http://platform-api:8000/api/v1/llm/models` |
| `CAPTAIN_WITDEV_TRANSCRIPTION_MODEL` | **Captain Whisper** — modelo oficial de transcrição de áudio do dossiê (select filtrado para aliases com áudio real) | `witdev_antigravity/gemini-3.1-pro-low` (recomendado) |

**Reinício necessário** após trocar a rota (mesmo comportamento do caminho legado: os engines são configurados no boot).

A rota witdev só ativa quando `CAPTAIN_LLM_ROUTE=witdev` **e** model **e** API key estão preenchidos —
config incompleta cai no caminho legado (zero regressão), e a tela do Captain mostra um
**banner amarelo "rota WitDev INATIVA"** listando exatamente o que falta.

## Captain Whisper — transcrição de áudio do dossiê

`Chatwit::AudioTranscriptionService` (`app/services/chatwit/audio_transcription_service.rb`) é o
fluxo canônico de transcrição do dossiê (`Conversations::DossierAudioService`):

- **Ativação:** basta a `CAPTAIN_WITDEV_PROXY_API_KEY` preenchida — independe de `CAPTAIN_LLM_ROUTE`
  e dos gates do Captain (feature/toggle/cota). Sem a key, o dossiê cai no Whisper legado.
- **Chamada:** `POST {proxy}/v1/chat/completions` com `input_audio` (mp3 base64, limite 15MB) e
  prompt jurídico verbatim (PT-BR, `[inaudível]`, falantes identificados, regionalismos preservados).
- **Allowlist de áudio:** só `witdev_antigravity/*` e `gemini-*`. Copilot devolve 200 OK com
  transcrição **alucinada** (descarta o áudio), codex dá HTTP 400 e Claude não tem entrada de áudio —
  o select do super admin já filtra e o serviço recusa alias fora da lista em runtime.
- **Cache:** resultado salvo em `attachment.meta['transcribed_text']` (mesmo slot do legado —
  os dois caminhos reaproveitam transcrições um do outro; áudios antigos são transcritos on-demand
  no próximo download do dossiê).
- Referência empírica: `witdev-platform-core/docs/agent-memory/witdev-audio-transcription.md`.

## O que muda em runtime (rota witdev ativa)

- **RubyLLM (global)**: `openai_api_key`/`openai_api_base` apontam para o proxy (`lib/llm/config.rb`).
- **Agents SDK** (Captain Assistant/Copilot): configurado no boot com proxy + alias (`config/initializers/ai_agents.rb`); `Concerns::Agentable#agent_model` retorna o alias.
- **Registry**: os aliases do catálogo são registrados no registry do RubyLLM como modelos chat OpenAI-compatible no boot (`config/initializers/zz_chatwit_llm_registry.rb` → `Chatwit::LlmProxy.register_models!`). O alias selecionado é registrado mesmo com catálogo fora do ar.
- **Task services** (`Captain::BaseTaskService`): credencial, `api_base` e modelo trocados pelo proxy/alias.
- **`Llm::BaseAiService`** (FAQ generator, contact notes/attributes, etc.): `setup_model` retorna o alias.

## O que NÃO muda (fica sempre no caminho legado)

- **Embeddings** (`Captain::Llm::EmbeddingService`): pinados nas keys OpenAI legadas — o proxy cobre apenas chat.
- **OpenAI Files API** (`Llm::LegacyBaseOpenAiService`, PDF/FAQ paginado): usa a key OpenAI legada.
- Todo o caminho legado do Chatwoot permanece intacto quando `CAPTAIN_LLM_ROUTE=chatwoot` (default).

## Arquivos

| Arquivo | Papel |
|---------|-------|
| `lib/chatwit/llm_proxy.rb` | **Novo.** Núcleo da rota: configs, fetch do catálogo (cache 5 min), registro de modelos |
| `config/installation_config.yml` | Novas configs `CAPTAIN_LLM_ROUTE` / `CAPTAIN_WITDEV_*` |
| `app/controllers/super_admin/app_configs_controller.rb` | Expõe os campos + select dinâmico do catálogo |
| `enterprise/app/controllers/enterprise/super_admin/app_configs_controller.rb` | Idem para instalações enterprise |
| `lib/llm/config.rb` | RubyLLM global → proxy quando witdev |
| `config/initializers/ai_agents.rb` | Agents SDK → proxy quando witdev |
| `config/initializers/zz_chatwit_llm_registry.rb` | Registro dos aliases no registry |
| `lib/captain/base_task_service.rb` | Credencial/base/modelo → proxy |
| `enterprise/app/services/llm/base_ai_service.rb` | Modelo → alias witdev |
| `enterprise/app/models/concerns/agentable.rb` | Modelo do agente → alias witdev |
| `enterprise/app/services/captain/llm/embedding_service.rb` | Embeddings pinados no legado |
| `app/services/chatwit/audio_transcription_service.rb` | **Novo.** Captain Whisper — transcrição via proxy (`input_audio`), allowlist de aliases, cache no meta |
| `app/services/conversations/dossier_audio_service.rb` | Dossiê usa Captain Whisper como canônico, Whisper legado como fallback |
| `enterprise/app/services/messages/audio_transcription_service.rb` | Erros distintos por gate (feature / toggle da conta / cota) |
| `app/views/super_admin/app_configs/show.html.erb` | Banner de rota WitDev incompleta |

## Troubleshooting

- **Select do modelo não lista nada**: o Chatwit não alcançou `platform-api` (rede `minha_rede`/overlay em prod). Digite o alias manualmente e verifique a rede/`CAPTAIN_WITDEV_CATALOG_URL`. Cache do catálogo: 5 min (`Rails.cache`, key `chatwit:witdev_llm_catalog`).
- **`ModelNotFoundError` após trocar o modelo**: reinicie o app (registro de aliases acontece no boot).
- **Erro 401 do proxy**: confira `CAPTAIN_WITDEV_PROXY_API_KEY` (key do LiteLLM).
