# Baixar Dossiê — Export de mensagens selecionadas em ZIP

> Feature Chatwit (fork) para uso em processos judiciais: o agente seleciona mensagens da
> conversa e baixa um ZIP com a transcrição completa, imagens, áudios em MP3 e as
> transcrições dos áudios (via Captain/Whisper).

## Visão geral

- **Entrada:** botão "Baixar Dossiê" (`i-ph-file-zip`) na toolbar do composer, ao lado do
  botão de link de pagamento (InfinitePay).
- **Seleção:** ao ativar, cada mensagem da conversa ganha um overlay clicável com checkbox.
  - Clique simples: alterna a seleção da mensagem.
  - `Shift`+clique ou `Alt`+clique: seleciona o intervalo entre a última mensagem clicada e a
    atual (estilo Excel/WhatsApp).
  - Barra fixa acima do composer mostra o contador, "Selecionar todas", "Cancelar" e
    "Baixar dossiê (ZIP)".
- **Saída:** ZIP `dossie-conversa-<display_id>-<data>.zip` com:

```
transcricao.txt          # transcrição completa: data/hora (America/Sao_Paulo), nome de
                         # exibição, conteúdo, referências aos anexos e transcrições inline
imagens/NNN-<nome>.jpg   # todas as imagens selecionadas
audios/NNN-<nome>.mp3    # todos os áudios convertidos para MP3
audios/transcricoes.txt  # transcrição de cada áudio, identificada pelo nome do arquivo
arquivos/NNN-<nome>      # demais anexos (vídeos, documentos)
```

`NNN` é um índice sequencial cronológico compartilhado entre as pastas — o mesmo número
referenciado em `transcricao.txt`.

## Arquitetura

### Backend (arquivos novos, zero modificação em código nativo)

| Arquivo | Papel |
|---------|-------|
| `app/controllers/api/v1/accounts/conversations/dossiers_controller.rb` | `POST /dossiers` (enfileira, fire-and-forget) e `GET /dossiers/:id` (status legado, mantido por compat) |
| `app/jobs/conversations/dossier_export_job.rb` | Orquestra a geração e **entrega o ZIP como nota privada na conversa** |
| `app/jobs/conversations/dossier_cleanup_job.rb` | Legado: purga blobs órfãos de dossiês antigos (pré fire-and-forget); não é mais agendado |
| `app/services/conversations/dossier_builder_service.rb` | Monta o ZIP (rubyzip), converte áudios, transcreve |
| `app/services/conversations/dossier_status.rb` | Status via `Redis::Alfred` (telemetria/debug; a UI não faz mais polling) |

Fluxo (**fire-and-forget**): `POST` valida `message_ids` → gera UUID → job na queue
`default` com o `user_id` do solicitante → ZIP montado em tempfile → blob no ActiveStorage
(MinIO) → **mensagem privada** (`private: true`, sender = agente solicitante) criada na
conversa com o ZIP anexado (`file_type: :file`) e conteúdo i18n
(`conversations.dossier.ready_note`, locale da conta). O agente não precisa manter o chat
aberto: a nota chega via websocket e o ZIP fica **permanente no histórico**, baixável de
qualquer lugar (inclusive mobile). Falha → nota privada com o erro
(`conversations.dossier.failed_note`) + `ChatwootExceptionTracker`.

> Limite de anexo: `MAXIMUM_FILE_UPLOAD_SIZE` (default 40MB). ZIP maior que isso falha na
> validação do attachment e vira nota de erro.

Reuso de infra existente do fork:
- **MP3:** `Audio::Mp3TranscodeService` (ffmpeg, cacheado em `attachment.playback_file`).
  Áudios que não são ogg/opus/webm nem mp3 (ex.: m4a/wav) ganham transcodificação ad-hoc
  com o mesmo comando ffmpeg; se falhar, o original entra no ZIP com a extensão original.
- **Transcrição (fluxo canônico — "Captain Whisper"):** `Chatwit::AudioTranscriptionService`
  envia o mp3 em base64 (`input_audio`) ao LiteLLM proxy da plataforma com o modelo de
  `CAPTAIN_WITDEV_TRANSCRIPTION_MODEL` (default `witdev_antigravity/gemini-3.1-pro-low`).
  Ativa sempre que a **WitDev Proxy API Key** estiver preenchida no Super Admin → Captain;
  não depende dos gates do Captain (feature/toggle/cota). Resultado cacheado em
  `attachment.meta['transcribed_text']`. Doc: `chatwitdocs/captain-witdev-llm-proxy.md`.
- **Transcrição (fallback legado):** sem a proxy key, cai no
  `Messages::AudioTranscriptionService` (enterprise, Captain + Whisper/OpenAI). Gates do
  serviço (feature `captain_integration`, `account.audio_transcriptions`, cota) se aplicam,
  agora com erro distinto por gate — sem Captain o ZIP sai com
  "[transcrição indisponível: <motivo>]".

### Frontend (components-next intocado no máximo possível)

| Arquivo | Papel |
|---------|-------|
| `app/javascript/dashboard/composables/useDossierSelection.js` | Estado global de seleção (modo ativo, ids, range Shift/Alt) |
| `app/javascript/dashboard/api/dossiers.js` | Client REST |
| `app/javascript/dashboard/components/widgets/conversation/dossier/DossierBar.vue` | Barra de ação — dispara a geração (fire-and-forget) e libera a tela |
| `ReplyBottomPanel.vue` (edit) | Botão na toolbar (padrão `NextButton`, igual ao payment link) |
| `ReplyBox.vue` (edit) | Liga o botão ao composable |
| `Message.vue` (edit) | Overlay de seleção + checkbox + highlight quando o modo está ativo |
| `MessagesView.vue` (edit) | Monta a `DossierBar` acima do composer |

Não há polling: ao enfileirar, a UI mostra o toast `DOSSIER.QUEUED`, sai do modo de
seleção e libera a tela. A entrega acontece pela nota privada na conversa.

## i18n

`CONVERSATION.FOOTER.DOSSIER` (tooltip) e bloco `CONVERSATION.DOSSIER.*` em
`en/conversation.json` e `pt_BR/conversation.json`.

## Decisões

- **Fire-and-forget + entrega por nota privada** em vez de polling com a tela travada:
  transcrever N áudios pode levar minutos; o agente dispara e segue trabalhando. O ZIP
  anexado à nota fica salvo no histórico da conversa, visível só para agentes (private),
  acessível de qualquer dispositivo — e some o risco de perder o download ao fechar a aba.
- **Sem purge**: o ZIP agora é anexo de mensagem (permanente, como qualquer arquivo do
  chat). O `DossierCleanupJob` ficou apenas para drenar blobs órfãos antigos.
- **Fuso fixo `America/Sao_Paulo`** rotulado como "horário de Brasília" no documento — para
  uso judicial o fuso precisa ser explícito e estável, não o fuso do navegador.
- **Sem migração de banco** — tudo usa `playback_file` e `meta.transcribed_text` que o fork
  já tem.
