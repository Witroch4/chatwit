# Captain Payment Phase 2 — fence de ownership do Socialwise

## Objetivo

Esta alteração impede o Socialwise de publicar efeitos de bot depois que uma conversa passa para o Captain Payment Phase 2.
O fence é baseado em estado durável no PostgreSQL e em um epoch monotônico; Redis continua sendo apenas o buffer descartável do debounce.

## Regras de posse

- Um `Captain::PaymentReviewTrigger` elegível e ainda presente bloqueia imediatamente o Socialwise.
- Um handoff em `additional_attributes['socialwise_handoff_at']` continua bloqueando mesmo sem a etiqueta canônica.
- `socialwise_ownership_epoch` ausente ou inválido equivale a `0`.
- Toda execução captura o epoch e revalida posse + epoch antes de cada efeito observável.
- A elegibilidade registrada no trigger é a fonte de verdade; o fence não reavalia o feature gate.
- `socialwise_owned?` e `can_publish?` leem handoff, trigger e epoch em um único snapshot curto sob lock da conversa. Nenhum lock PostgreSQL atravessa webhook ou provider.

## Aquisição pelo Captain

`Integrations::SocialwiseFlow::OwnershipGuard#pause_for_phase2!` trava primeiro a conversa, preserva atributos alheios e grava:

- `socialwise_handoff_at`, com precisão de microssegundos;
- `socialwise_handoff_by = captain_payment_phase2`;
- incremento de `socialwise_ownership_epoch`;
- `status = open` e `waiting_since = nil`.

Depois do commit, o guard readquire o lock da conversa e compara a identidade exata que acabou de instalar (`epoch`, `handoff_at` e `handoff_by`). A limpeza best-effort de `MESSAGES`, `FIRST_AT`, `LAST_AT` e `ACTIVE` só ocorre enquanto essa identidade ainda é atual e com o lock mantido; se resolve/rearm já instalou uma geração sucessora, o cleanup antigo é ignorado. Falhas na segunda aquisição/reload são contidas depois do fence durável, evitando retry e novo incremento de epoch; falhas da primeira persistência continuam propagando. Cada delete Redis permanece isolado contra falhas e o lock Redis nunca é apagado sem token de proprietário.

## Pontos protegidos

O fence é aplicado no ingresso normal e concatenado, ao redor do webhook Socialwise, nas escritas/agendamento do debounce e antes de mensagens, ações, reações, payloads ricos, providers diretos e fallbacks.
Os delegates WhatsApp e Instagram recebem um callback de ownership para revalidar entre persistência local e provider. O caminho Facebook faz a mesma revalidação diretamente.

Respostas autorizadas contendo texto e `action=handoff|resolve` publicam o texto primeiro e aplicam a ação por último. O epoch original é propagado pelos caminhos normal, button e rescue; imediatamente antes da mutação, epoch e ownership são validados no mesmo snapshot sob lock. O handoff grava atributos, `waiting_since` e status aberto em uma única atualização atômica; o evento `CONVERSATION_BOT_HANDOFF` só é emitido depois do commit e sem lock, portanto falha no dispatcher não reverte o estado durável. Uma pausa Captain que obtém o lock primeiro preserva integralmente handoff, epoch e atributos e não gera evento. A liberação no resolve pertence ao `SocialwiseFlowListener`/`OwnershipGuard`; a action não mantém um writer stale para limpar handoff.

O provider de typing é construído antes do checkpoint final, e o efeito `mark_read_with_typing` só ocorre depois de nova validação. Handoffs humanos também recarregam e travam a conversa antes do merge, substituindo a origem do handoff sem apagar o epoch ou atributos concorrentes.

Quando um provider WhatsApp já aceitou uma mensagem e devolveu `message_id`, a persistência local de `source_id` é tratada como bookkeeping do efeito concluído. Mesmo que a posse mude durante a chamada externa, o Chatwit grava esse identificador sem disparar outro provider ou fallback.

## Debounce e epoch imutável

Cada item do buffer carrega o `ownership_epoch` capturado no ingresso. O mesmo valor segue como argumento do `SocialwiseDebounceJob` e parâmetro obrigatório do `DebounceProcessorService`; jobs legados sem epoch falham fechado e o serviço concatenado nunca recaptura/reclassifica um lote antigo.

O claim do lote é um script Redis atômico:

- processa apenas itens do epoch esperado com `timestamp <= cutoff`;
- descarta itens legados, malformados e de epoch anterior;
- preserva itens do mesmo epoch posteriores ao cutoff e itens de epoch futuro;
- recompõe `MESSAGES`, `FIRST_AT`, `LAST_AT` e TTL a partir dos itens preservados.

`ACTIVE` e `LOCK` usam UUID, `SET NX EX` e compare-and-delete. Um job antigo nunca remove o token de um sucessor. Se o compare-and-delete liberar `ACTIVE`, ou retornar zero porque o token já expirou e `ACTIVE` está ausente, o job examina o buffer, deriva um epoch válido, revalida o guard e agenda um sucessor. Se `ACTIVE` contém o token de outro job, não há scan nem wake duplicado. Entradas sem epoch válido não acordam processamento.

## Resolve atrasado

`SocialwiseFlowListener` delega a liberação ao guard usando `event.timestamp` como cutoff e ordem de lock `conversation -> trigger`.
Somente trigger/handoff existentes no instante do evento são liberados. Triggers, handoffs e etiquetas de uma geração posterior são preservados, inclusive quando a aquisição ocorre no mesmo segundo do resolve.

Quando o resolve libera um handoff antigo e não existe trigger presente posterior ao cutoff, a etiqueta canônica também é removida — inclusive se o trigger anterior já estiver ausente, cancelado ou consumido. Isso restaura a borda de rearm para uma futura readição da etiqueta.

## Validação

Os specs focados cobrem ingresso, epoch imutável, pausa, cleanup Redis protegido por identidade de geração, falha no reacquire pós-commit, actions atômicas, dispatch pós-commit, claim Lua com Redis real, tokens ACTIVE/LOCK, expiração de ACTIVE, wake de lote retido, providers, bookkeeping `source_id`, fallbacks, debounce, human takeover, rollback atômico e corridas de cutoff/sucessor. A suíte final da Task 4 executou `98 examples, 0 failures`.

## Limites / Task 10

- Adicionar um permit fence genérico ao `SendReplyJob`/caminho async do Agent Bot, preservando a semântica composta `text + action`.
- Renovar/heartbeat do lock Redis de processamento quando uma operação puder ultrapassar o TTL fixo atual de `60s`.
