# Captain WitDev — Modelos Canônicos

Data: 2026-07-18

## Objetivo

Fazer o fluxo novo do Captain, ativado por `CAPTAIN_LLM_ROUTE=witdev`, usar o catálogo
canônico da plataforma para listar, persistir, validar e executar modelos generativos.
A rota legada do Chatwoot deve permanecer funcional e sem alterações de comportamento.

Fonte normativa:
`/home/wital/witdev-platform-core/docs/LLM-CANONICAL-FLOW-ALL-APPS.md`.

## Escopo

O ajuste cobre as superfícies generativas do Captain que executam pelo LiteLLM da
plataforma:

- modelo global `CAPTAIN_WITDEV_MODEL`;
- preferências por conta para editor, assistente, copilot e sugestão de etiquetas;
- modelo específico da revisão de pagamento fase 2;
- modelo `CAPTAIN_WITDEV_TRANSCRIPTION_MODEL` do Captain Whisper.

Ficam fora do ajuste:

- `CAPTAIN_LLM_ROUTE=chatwoot` e todo o catálogo legado de `config/llm.yml`;
- embeddings, OpenAI Files API e a transcrição nativa `whisper-1`, que continuam no
  caminho legado já existente;
- mudanças no catálogo, seed ou roteamento da Witdev Platform Core.

## Invariantes

1. O Chatwit lista modelos somente por `Chatwit::LlmProxy`, que consulta
   `platform-api /api/v1/llm/models` server-to-server.
2. O browser nunca recebe a chave do proxy e nunca chama LiteLLM ou OmniRoute.
3. O valor persistido é sempre o alias canônico exato publicado em `value`/`alias`.
4. Modelo ausente, inativo ou oculto não pode ser gravado nem executado.
5. Catálogo com origem de fallback pode preservar a visualização, mas não autoriza
   gravação ou execução.
6. Catálogo indisponível não ativa `config/llm.yml` como fallback do fluxo WitDev.
7. Uma resposta central não vazia não é mesclada com modelos locais.
8. A rota Chatwoot mantém validação, defaults, chaves e execução atuais.

## Estado implementado

`Chatwit::LlmProxy` preserva os metadados necessários para autorização, incluindo
`source`, `active`, `hidden` e capacidades. O catálogo operacional é restrito à
origem `litellm_proxy`, com modelos ativos e não ocultos.

Na rota WitDev, o endpoint de preferências por conta expõe descritores do catálogo
operacional e o resolvedor central valida aliases antes de persistência e antes de
execução. As preferências por funcionalidade têm precedência sobre o default global;
aliases ausentes, inativos, ocultos ou de catálogo indisponível falham fechados.

O modelo global do Super Admin, o seletor da fase 2 e o Captain Whisper usam
`Chatwit::LlmProxy`. O Whisper resolve seu alias canônico pelo catálogo operacional
e mantém `audio_capable?` como guarda empírica adicional de compatibilidade de
transporte, baseada na allowlist existente — não em uma capacidade de áudio publicada
pelo catálogo.
`config/llm.yml` permanece legado e inalterado.

## Arquitetura implementada

### Catálogo e autorização

`Chatwit::LlmProxy` continua sendo o único adaptador do Chatwit para o contrato
central. Ele preserva a origem e os metadados normalizados de cada descritor,
sem inferir provider ou capacidades pelo nome do alias.

O catálogo normalizado bruto é um detalhe interno do adaptador. Para os consumidores,
ele expõe duas noções separadas:

- catálogo operacional: somente resposta com origem `litellm_proxy`, contendo modelos
  ativos e não ocultos, usado para validar gravação e execução.
- opções de apresentação: derivadas exclusivamente de `operational_models` e entregues
  à UI junto do status do catálogo e do metadado `selection_valid`.

`Chatwit::LlmProxy.resolve_model!` recebe o alias desejado e devolve a string exata do
alias autorizado ou um erro explícito. Nenhum chamador reconstrói aliases ou implementa
validação própria por prefixos.

### Preferências por conta

O endpoint existente `captain/preferences` mantém o payload legado quando a rota
Chatwoot está ativa. Quando a rota WitDev está ativa, os recursos generativos usam
descritores vindos do catálogo central:

- `editor`;
- `assistant`;
- `copilot`;
- `label_suggestion`.

Os recursos `audio_transcription` e `help_center_search` continuam com a configuração
legada porque suas execuções não foram migradas para o caminho generativo WitDev.

Ao salvar uma preferência generativa no fluxo WitDev, o backend exige que o alias
esteja no catálogo operacional. Se o catálogo estiver indisponível ou o alias tiver
sumido, a atualização responde com erro de validação e preserva a configuração
anterior.

### Resolução em runtime

Para o fluxo WitDev, a escolha do modelo segue esta precedência:

1. alias por funcionalidade salvo na conta;
2. `CAPTAIN_WITDEV_MODEL` como default global;
3. erro fechado se nenhum alias operacional estiver disponível.

Antes da chamada ao LiteLLM, o alias final é resolvido novamente contra o catálogo
operacional. Um alias antigo que deixou de existir não é substituído silenciosamente.
O erro orienta o administrador a selecionar outro modelo.

Os serviços usam as seguintes chaves:

- editor e tarefas gerais de escrita: `editor`;
- resposta sugerida/copilot: `copilot`;
- sugestão de etiqueta: `label_suggestion`;
- agentes e cenários do Captain: `assistant`;
- revisão de pagamento fase 2: `phase2_model`, com fallback para o default global;
- Captain Whisper: `CAPTAIN_WITDEV_TRANSCRIPTION_MODEL`, resolvido como alias
  canônico e protegido pela guarda de transporte `audio_capable?`, baseada na
  allowlist empírica existente.

### Interface

Os dropdowns continuam usando os componentes existentes. No fluxo WitDev eles consomem
os descritores operacionais para exibir label e provider publicados pelo catálogo,
além do status do catálogo e do metadado `selection_valid` de cada funcionalidade. Se
o catálogo não estiver disponível, o controle não oferece aliases locais e informa
que a seleção central não pôde ser carregada.

Um alias persistido que não está mais autorizado permanece visível apenas como estado
inválido para exigir nova seleção; ele não entra na lista de opções e não executa.

### Compatibilidade legada

Toda decisão nova é condicionada a `Chatwit::LlmProxy.route_witdev?`. Quando a rota é
Chatwoot:

- `Llm::Models` continua fornecendo providers, modelos, defaults e validação;
- `CAPTAIN_OPEN_AI_MODEL` continua sendo o modelo global;
- OpenAI/Gemini keys e endpoints permanecem inalterados;
- specs existentes do caminho legado continuam passando sem adaptação de expectativa
  funcional.

## Tratamento de erros

- Falha HTTP, timeout ou payload vazio do catálogo: UI indisponível para novas
  seleções e execução WitDev falha antes da chamada ao proxy.
- Origem de fallback: pode ser exibida como degradação, mas não autoriza persistência
  nem execução.
- Alias ausente/inativo/oculto: erro de validação com orientação para selecionar um
  modelo publicado.
- Alias válido que falha no proxy por erro transitório: mantém o tratamento de erro da
  chamada LLM já existente; o catálogo não mascara erro de execução.

## Testes

O trabalho seguiu TDD e cobriu:

- normalização dos metadados e da origem do catálogo em `Chatwit::LlmProxy`;
- autorização somente para aliases ativos, visíveis e de origem operacional;
- payload dinâmico de preferências apenas na rota WitDev;
- preservação integral do payload e validação legados na rota Chatwoot;
- rejeição de gravação quando alias ou catálogo não são autorizados;
- precedência modelo por conta → modelo global;
- falha fechada para alias removido;
- uso das chaves corretas por editor, copilot, etiquetas e assistente;
- validação dos aliases da fase 2 e Captain Whisper;
- renderização dos dropdowns com o descritor central, sem fallback local.

Validações focadas incluíram RSpec nos serviços/controllers/models alterados, Vitest
nos componentes/store afetados e ESLint/RuboCop somente nos arquivos tocados antes de
ampliar a suíte.

## Documentação de entrega

`chatwitdocs/captain-witdev-llm-proxy.md` foi atualizado com o fluxo por conta, as
regras de falha fechada e os passos operacionais para substituir aliases removidos.
