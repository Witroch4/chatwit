# Captain — rota WitDev e modelos canônicos

## Fonte de verdade e limites da rota

O documento normativo único para catálogo, seleção e roteamento de modelos é
[`LLM-CANONICAL-FLOW-ALL-APPS.md`](/home/wital/witdev-platform-core/docs/LLM-CANONICAL-FLOW-ALL-APPS.md).
Este guia descreve somente como o Captain consome esse contrato; ele não mantém
nem reproduz uma lista local de modelos.

O Captain tem duas rotas configuradas em **Super Admin → Settings → Captain →
LLM Route**:

| Rota | Comportamento |
| --- | --- |
| `chatwoot` | Caminho legado, com modelos, chaves e validação já existentes do Chatwoot. |
| `witdev` | Caminho canônico: catálogo via `platform-api` e execução no LiteLLM proxy da plataforma. |

Na rota WitDev, o Chatwit consulta o catálogo apenas por
`Chatwit::LlmProxy`, que faz uma chamada server-to-server a
`platform-api /api/v1/llm/models`. O browser não chama LiteLLM, OmniRoute ou o
catálogo diretamente e nunca recebe a chave do proxy. O valor armazenado e
enviado é sempre o alias canônico publicado pelo catálogo.

## Catálogo operacional e autorização

O catálogo pode ser usado para autorizar gravação ou execução somente quando a
origem de topo da resposta atende à regra exata:

```text
source == "litellm_proxy"
```

Além dessa origem, o alias precisa estar presente no catálogo e não pode estar
marcado como inativo (`active: false`) ou oculto (`hidden: true`). Essa checagem
é centralizada em `Chatwit::LlmProxy.resolve_model!`; nenhum consumidor deve
inferir provider, capacidade ou validade pelo texto do alias.

Resposta vazia, erro de rede, timeout, origem ausente, `local_fallback` ou outra
origem não operacional tornam o catálogo indisponível para autorização. Modelos
locais, recomendações e `config/llm.yml` não são mesclados ao catálogo central e
não reautorizam aliases removidos.

## Seleção global e por conta

`CAPTAIN_WITDEV_MODEL` é o default global da rota WitDev. Para os 10 recursos
generativos do Captain e do Help Center, a precedência é:

1. alias salvo na preferência da conta para o recurso;
2. `CAPTAIN_WITDEV_MODEL`;
3. falha fechada se o alias final não for operacional.

Os recursos e seus usos em runtime são:

| Preferência | Uso no Captain |
| --- | --- |
| `editor` | tarefas gerais de escrita do Captain (default) |
| `assistant` | Agents SDK e avaliação de conclusão de conversa |
| `copilot` | sugestões de resposta |
| `label_suggestion` | sugestões de etiquetas |
| `document_faq_generation` | geração de FAQs a partir de documentos |
| `conversation_faq_generation` | geração de FAQs a partir de conversas |
| `pdf_faq_generation` | geração de FAQs a partir de PDFs |
| `help_center_article_generation` | geração de artigos da Central de Ajuda |
| `onboarding_content_generation` | geração de conteúdo de onboarding |
| `help_center_query_translation` | tradução de consultas da Central de Ajuda |

O modelo da revisão de pagamento fase 2 é separado: usa o alias do inbox
(`phase2_model`) quando preenchido e, caso contrário, o default global. O modelo
do Captain Whisper é configurado separadamente em
`CAPTAIN_WITDEV_TRANSCRIPTION_MODEL`, resolvido como alias canônico pelo catálogo
operacional e submetido à guarda empírica de compatibilidade de transporte
`audio_capable?`. Essa guarda usa a allowlist existente de famílias de aliases; ela
não deriva uma capacidade de áudio publicada pelo catálogo.

## Falha fechada e respostas de validação

Com `CAPTAIN_LLM_ROUTE=witdev`, a execução é exclusivamente pelo proxy. Catálogo
indisponível, alias removido/inativo/oculto ou configuração incompleta não acionam
chaves, endpoint, modelo, hook de conta ou catálogo legados. A falha ocorre antes
da chamada ao modelo.

As APIs de preferências do Captain e de criação de inbox da fase 2 respondem
**422 Unprocessable Entity** para um alias inválido ou indisponível e não
persistem a seleção solicitada. No Super Admin, uma alteração inválida dos campos
globais é rejeitada e o valor existente é preservado. O dropdown da rota WitDev
não oferece uma lista local quando o catálogo não é operacional; uma seleção
persistida que deixou de ser válida aparece como inválida até ser substituída.

No boot, aliases operacionais são pré-registrados e o default do Agents SDK é resolvido.
Se o catálogo estiver indisponível nesse momento, uma resolução autorizada após o TTL
registra o alias sob demanda, sem restart. Reinicie a aplicação somente após alterar
configurações globais da rota, proxy ou modelo, para reaplicar o default do Agents SDK.

## Como substituir um alias que saiu do catálogo

1. Confirme que `CAPTAIN_LLM_ROUTE` continua em `witdev` e que
   `CAPTAIN_WITDEV_CATALOG_URL` alcança o `platform-api`.
2. Aguarde a atualização do catálogo central ou o TTL de cache do Chatwit (cinco
   minutos). Se a origem não for `litellm_proxy`, corrija o catálogo/rota na
   plataforma; não digite nem recoloque o alias removido localmente.
3. No Super Admin, selecione um alias atualmente publicado para
   `CAPTAIN_WITDEV_MODEL` e, se aplicável, para a transcrição.
4. Em cada conta afetada, abra as preferências do Captain e substitua a seleção
   inválida do recurso correspondente. Para a fase 2, recrie/atualize a
   configuração do inbox com um alias publicado.
5. Reinicie a aplicação após mudar o default global e repita a operação que
   falhava. O alias removido não recebe substituição automática.

## Fluxos que permanecem legados

O escopo WitDev cobre as chamadas generativas de chat descritas acima. Estes
fluxos continuam no caminho legado, inclusive quando a rota WitDev está ativa:

- embeddings;
- OpenAI Files API;
- Whisper nativo (`whisper-1`).

O Captain Whisper via proxy é uma integração específica de transcrição e não
altera o comportamento do Whisper nativo. `config/llm.yml` e o caminho
`CAPTAIN_LLM_ROUTE=chatwoot` também permanecem legados e inalterados.

## Diagnóstico rápido

- **Catálogo sem opções ou seleção desabilitada:** confirme a conectividade
  interna com `CAPTAIN_WITDEV_CATALOG_URL` e a origem `litellm_proxy` retornada
  pela plataforma. Não use uma lista manual como contorno.
- **Erro 422 ao salvar:** o alias não está operacional; atualize-o pela lista
  atual do catálogo.
- **Falha em runtime após uma remoção:** corrija o default global ou a preferência
  por conta/inbox que ainda guarda o alias antigo; o comportamento esperado é
  falhar fechado.
- **Erro de autenticação no proxy:** confira
  `CAPTAIN_WITDEV_PROXY_API_KEY`, que é a credencial do LiteLLM proxy.
