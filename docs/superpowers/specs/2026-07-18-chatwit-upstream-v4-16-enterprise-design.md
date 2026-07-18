# Chatwit Upstream 4.16 Enterprise Sync Design

## Objetivo

Mesclar `upstream/develop` no fork Chatwit por meio de um merge Git real, atualizar a
base de Chatwoot 4.13 para 4.16, preservar todas as customizações fork-only e provar
que o overlay Enterprise — especialmente Captain, catálogo LLM e Payment Phase 2 —
continua funcional antes de integrar em `develop` e publicar em produção.

## Estado inicial comprovado

- Branch de origem: `develop` em `6b868b58e5885474d0260db9347b4f69410a72a5`.
- Merge-base: `437dd9d38ce9c12ee5edbbde81e931e652feba30`, o sync 4.13 registrado.
- Upstream: `a752e56765a46bb62571932fe6bebf0b71b31b61`, merge da release 4.16.0.
- Divergência real: 405 commits upstream e 393 PRs upstream ausentes no fork.
- Sobreposição: 157 arquivos modificados dos dois lados.
- Previsão por `git merge-tree`: 76 conflitos, dos quais 28 são ícones binários de branding.
- Baseline: 189 exemplos Ruby e 11 testes frontend relevantes passaram antes do merge.
- Backup: `backup/pre-upstream-sync-20260718`.
- Worktree: `.worktrees/upstream-v4.16.0-20260718`, branch
  `sync/upstream-v4.16.0-20260718`.

## Estratégia de integração

Usar `git merge --no-ff upstream/develop`. Não usar rebase, squash ou cherry-pick para
os commits upstream. Cada conflito textual será resolvido após comparar base, fork e
upstream; nenhum conjunto de conflitos será escolhido em massa por lado.

Os assets binários `public/*icon*.png` e `public/favicon*.png` manterão as versões do
Chatwit. O `public/manifest.json` será mesclado manualmente para manter identidade/PWA
Chatwit e absorver campos técnicos compatíveis do upstream.

O resultado precisa fazer `git rev-list --count HEAD..upstream/develop` retornar zero e
ter o novo upstream como ancestral do merge commit.

## Enterprise e Captain

O upstream 4.16 adiciona `Llm::FeatureRouter`, preferências de modelo reforçadas e
roteamento específico para Captain V2. Esses recursos serão preservados integralmente
no caminho legado `CAPTAIN_LLM_ROUTE=chatwoot`.

Na rota `CAPTAIN_LLM_ROUTE=witdev`, a precedência será:

1. alias canônico salvo por conta para qualquer um dos 10 recursos generativos:
   `editor`, `assistant`, `copilot`, `label_suggestion`, `document_faq_generation`,
   `conversation_faq_generation`, `pdf_faq_generation`,
   `help_center_article_generation`, `onboarding_content_generation` ou
   `help_center_query_translation`;
2. `CAPTAIN_WITDEV_MODEL`;
3. falha fechada se o catálogo não tiver `source == "litellm_proxy"` ou o alias estiver
   ausente, inativo ou oculto.

`Llm::FeatureRouter.resolve` será o ponto comum de chamada. Para os 10 recursos
generativos na rota WitDev, ele delegará autorização a
`Chatwit::CaptainModelResolver`; para `audio_transcription`, `help_center_search` e toda
a rota legado, manterá a resolução upstream por `config/llm.yml`.

`Captain::BaseTaskService`, `Concerns::Agentable`, `Llm::BaseAiService` e os serviços
Enterprise de sugestão continuarão consumindo o roteador upstream. Credenciais e
endpoint serão escolhidos pela rota: proxy e chave WitDev na rota canônica, hooks/chaves
Chatwoot na rota legado. Uma configuração WitDev incompleta nunca poderá cair no legado.

Embeddings, OpenAI Files API e Whisper nativo permanecerão legados. O Captain Whisper
via proxy continuará separado e autorizado pelo catálogo operacional.

O Payment Phase 2 manterá `phase2_model` por inbox, resolvido contra o mesmo catálogo
operacional, com 422 em alias inválido e sem persistência parcial.

## Customizações fork-only protegidas

O merge deve preservar e validar:

- bot global `Chatwit::PlatformBot` e inicialização em `config/initializers/00_chatwit.rb`;
- SocialWise Flow, debounce, ownership fence, respostas sync/async e Lead Sync;
- JusMonitorIA, assinatura HMAC e respostas/ações;
- QUICK_REPLY em WhatsApp, Instagram e Facebook;
- templates WhatsApp, mappers e rich messages em `components-next/`;
- Evolution Go como provider de `Channel::Whatsapp`;
- Webhook access token, rotas e permissões mínimas do Agent Bot;
- PWA mobile isolada do desktop e Web Push/VAPID;
- branding Chatwit, manifest e ícones;
- Redis keys, i18n e documentação `chatwitdocs/`.

## Resolução por domínio

### Core, autenticação e webhooks

Absorver os novos feature flags/API guards do upstream em controllers e listeners sem
remover permissões do bot global. Preservar assinaturas atuais de jobs e incluir dados de
conta adicionados pelo upstream aos webhooks.

### WhatsApp e canais

Combinar os novos fluxos de coexistence, referral e embedded-signup do upstream com
`extract_interactive_data`, dispatch de templates e Evolution Go. O método de criação de
mensagem continuará mesclando o payload interativo; os testes cobrirão Cloud API e
Facebook API.

### Frontend e mobile

Manter rich bubbles e renderização de áudio fork-only, absorvendo mudanças de acessibilidade,
report de mensagens Captain e configurações de inbox. O branch mobile continuará apenas
condicional em tela pequena, sem substituir stores/composables do desktop.

### Schema e configuração

Usar a versão/migrações upstream e manter todas as tabelas/colunas fork-only. Mesclar
`config/integration/apps.yml`, `config/schedule.yml`, `config/routes.rb`, locales e Redis
keys de forma aditiva. Não introduzir `version:` em Compose.

## Tratamento de erros

- Conflito não compreendido bloqueia a integração até comparação de base/ours/theirs.
- Catálogo WitDev indisponível ou não operacional gera erro explícito antes de qualquer
  chamada LLM.
- Falha de spec Enterprise é tratada como regressão do merge, não como teste descartável.
- Falha de migration/boot bloqueia build e deploy.
- Rollout só é concluído quando app e Sidekiq usam o mesmo digest e todas as tarefas estão
  `Running` com `UpdateStatus=completed`.

## Matriz de validação

1. Estrutural: zero conflitos Git e zero marcadores em Ruby, Vue, JS/TS, YAML/JSON e ERB.
2. Histórico: upstream-ahead zero e merge-base atualizado.
3. Enterprise/Captain: specs de `spec/enterprise/**/captain`, `agentable`,
   `base_ai_service`, áudio, preferências, feature router e Payment Phase 2.
4. Fork-only Ruby: SocialWise, JusMonitorIA, webhooks, WhatsApp, rich mappers e Evolution Go.
5. Frontend: Vitest de Captain/model dropdown, rich messages/mobile e ESLint nos arquivos
   alterados.
6. Qualidade Ruby: RuboCop nos arquivos Ruby alterados.
7. Banco/boot: `db:prepare`/migration check e boot Rails em `RAILS_ENV=test`.
8. Build: imagem Enterprise por `./build.sh`, push com tag imutável e `latest`.
9. Produção: app e Sidekiq no digest novo, tarefas estáveis e endpoint público HTTP 200.

## Critérios de conclusão

O trabalho só termina quando o upstream 4.16 estiver ancestral de `develop`, todas as
customizações listadas tiverem evidência estrutural e comportamental, as validações OSS e
Enterprise estiverem verdes, `origin/develop` apontar para o merge local e produção estiver
convergida no digest construído dessa revisão.
