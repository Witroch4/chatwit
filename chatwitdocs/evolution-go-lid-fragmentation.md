# Fragmentação de contato por LID (Evolution Go) — causa e correção

## Sintoma

Uma única conversa de WhatsApp aparece **dividida em dois contatos/conversas** no Chatwit:
as mensagens **recebidas** caem no contato com o telefone real (ex.: `+558581058203`) e as
mensagens **enviadas/echo** caem num contato-fantasma cujo "número" é um valor grande e sem
sentido (ex.: `+25984669642815`). No celular, é tudo uma conversa só.

## Causa-raiz

O WhatsApp está migrando o endereçamento de conversas para **LID** (*LinkedID*, privacidade).
O mesmo contato passa a chegar ora endereçado por telefone (`558581058203@s.whatsapp.net`),
ora por LID (`25984669642815@lid`). O `25984669642815` **não é telefone** — é o LID do contato.

Três camadas contribuíam:

1. **Chatwit** (`app/services/evolution_go/webhook_service.rb`) deriva a identidade do contato do
   *user-part* do JID (`extract_number`). Um JID `@lid` vira "telefone" = o número do LID.
2. **Echo (fromMe)** (`app/services/whatsapp/incoming_message_base_service.rb#set_contact_from_echo`)
   usa o campo `to` (= Chat) como telefone do contato → cria o contato-fantasma com o LID.
3. **Evolution Go** (`pkg/whatsmeow/service/whatsmeow.go`, handler `*events.Message`) só normalizava
   LID→telefone para **mensagens recebidas** quando `Sender=@lid` **e** `SenderAlt=@s.whatsapp.net`.
   Nos **echoes (fromMe)** o `Sender` é o próprio número, então a condição era falsa, o `Chat`
   permanecia `@lid`, e o campo correto (`RecipientAlt`, telefone real do destinatário) nunca era
   consultado. Resultado: echoes vazavam o LID.

## Correção

### 1. Evolution Go (raiz) — `pkg/whatsmeow/service/whatsmeow.go`
- No swap existente, a atualização de `Chat` passou a valer só para recebidas (`!IsFromMe`),
  evitando trocar o `Chat` do echo pelo **próprio** número.
- Novo bloco normaliza `Chat @lid → telefone` em todos os casos:
  - `IsFromMe` → usa `RecipientAlt` (telefone do destinatário);
  - recebida → usa `SenderAlt`;
  - fallback → resolve LID→PN pelo store do whatsmeow (`Store.LIDs.GetPNForLID`).

### 2. Chatwit (defesa em profundidade) — `webhook_service.rb`
- `extract_jid` passa a preferir o alternativo `@s.whatsapp.net` do evento
  (`data.Info.RecipientAlt` p/ echo, `data.Info.SenderAlt` p/ recebida) quando o `Chat` é `@lid`.
  Se não houver alternativo, mantém o comportamento anterior (sem regressão).

### 3. Reparo de dados (produção)
- Mapa autoritativo LID↔telefone: tabela `whatsmeow_lid_map` no banco **`evolution_go_auth`**
  (`lid`, `pn`). O `pn` bate com `contacts.phone_number` (dígitos).
- Contatos-fantasma são mesclados no contato real via `ContactMergeAction`
  (base = telefone real, mergee = fantasma LID).

## Diagnóstico de referência (2026-07, conta 3 / inbox 116 "Sem robô")
- 89 contatos no inbox; **44 fantasmas LID** (~metade). Único inbox evolution_go afetado.
- 43/44 com mapeamento; **40 com gêmeo real** (→ 40 merges). ~4 órfãos.
- Caso Dra. Amanda: LID `25984669642815` (contato 3178) ↔ `558581058203` (contato 3180),
  confirmado em `whatsmeow_lid_map`.

## 9º dígito brasileiro — JÁ é tratado (não requer trabalho extra)

O 9º dígito **não** é um problema para o fix de LID, porque o Chatwit já canonicaliza isso:
`processed_waid` → `Whatsapp::PhoneNumberNormalizationService` + `Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer`.

- `normalize` → forma canônica é o **13 dígitos com o 9** (`55{DDD}9{num}`).
- `equivalents` → devolve as **duas** formas (com-9 e sem-9).
- O service procura um `contact_inbox` existente sob **qualquer** equivalente e reusa o `source_id`
  dele; só usa a canônica quando o contato é novo.

Consequência: quando o fix de LID resolve o LID para o telefone **sem-9** (`558581058203`, formato
do `whatsmeow_lid_map`), o `processed_waid` procura os equivalentes `[5585981058203, 558581058203]`
e **encontra o contato com-9 já existente** (ex.: 3180) → anexa nele, **sem criar novo fragmento**.

Por que LID escapava desse tratamento: `BrazilPhoneNormalizer.handles_country?` exige prefixo `55`.
Um LID (`25984669642815`) não começa com 55 → o normalizador não atua → o `source_id` fica o LID cru.
Por isso o LID precisa ser resolvido **na origem** (Evolution Go) / na defesa do webhook, e o 9º dígito
segue sendo resolvido pelo caminho já existente.

## Como verificar em produção
```sql
-- fantasmas LID no inbox (source_id não começa com 55 e é longo)
SELECT count(*) FROM contact_inboxes
WHERE inbox_id=<ID> AND source_id ~ '^[0-9]+$'
  AND length(source_id)>=13 AND source_id NOT LIKE '55%';

-- mapeamento (banco evolution_go_auth)
SELECT lid, pn FROM whatsmeow_lid_map WHERE lid='<LID>';
```
