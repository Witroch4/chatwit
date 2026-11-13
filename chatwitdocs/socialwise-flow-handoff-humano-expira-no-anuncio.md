# Socialwise Flow — handoff humano antigo não bloqueia mais o robô num clique de anúncio

## Problema (13/11/2026, conversa #3616, caixa "WhatsApp - ANA")

Uma resposta humana grava `socialwise_handoff_at` / `socialwise_handoff_by = agent_reply`
na conversa (`ProcessorService#should_run_processor?`). Esse handoff só saía quando a conversa
era resolvida. Conversa que ficou aberta com a pessoa (a #3616 desde 15/07) bloqueava o robô
para sempre: `bot_should_respond?` só aceita conversa aberta quando não há handoff.

Quando o lead voltava por um anúncio (cliques de 12/11 17:36 e 13/11 08:17), a mensagem caía
na conversa antiga e o robô não era chamado. Medido em 36 h na caixa ANA: 12 de 14 conversas
antigas com handoff ficaram sem resposta do robô.

## O que mudou

`ProcessorService#release_stale_human_handoff_for_ad_return` roda antes de `bot_should_respond?`.
Libera o handoff, via `OwnershipGuard#release_stale_human_handoff!`, só quando **todas** as
condições valem:

- a mensagem é do contato e traz `content_attributes.referral` (clique em anúncio/post);
- a conversa está `open`;
- `socialwise_handoff_by` é de resposta humana (`agent_reply`, `human_reply`, `external_echo`);
- `socialwise_handoff_at` tem mais de **24 h** (`STALE_HUMAN_HANDOFF_AFTER`). Como o campo é
  regravado a cada resposta humana, ele é o horário da última resposta de uma pessoa.

Efeito: remove `socialwise_handoff_at/by` e soma 1 ao `socialwise_ownership_epoch`
(cancela publicações em voo). Não mexe em gatilhos nem em labels de revisão de pagamento.

## O que NÃO muda

- Mensagem sem `referral` (arquivo, "ok", resposta ao atendente) continua com a pessoa, por mais
  antigo que seja o handoff: a maioria das mensagens nas conversas antigas é atendimento humano em curso.
- Handoff executado pelo Socialwise (`bot`) e `captain_payment_phase2` nunca expiram por tempo.
- "Resolver" a conversa continua devolvendo o robô (`release_for_resolve!`).
- Resposta humana há menos de 24 h continua bloqueando o robô.

## Limite conhecido

O clique de anúncio só é reconhecido quando a mensagem carrega `referral`. Na #3616 a segunda mensagem
(13/11 08:17) veio sem esse campo; a primeira (12/11 17:36) tinha. Basta a primeira para o robô voltar.

## Testes

`spec/lib/integrations/socialwise_flow/ownership_guard_spec.rb` (`#release_stale_human_handoff!`) e
`spec/lib/integrations/socialwise_flow/processor_service_spec.rb` (`lead returning from an ad after a stale human handoff`).
