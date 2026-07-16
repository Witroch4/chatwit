# Seletor de respostas prontas no compositor

Data: 2026-07-15

## Comportamento entregue

No compositor de respostas públicas do dashboard desktop, o primeiro botão da barra de ações — antes do botão de emoji — abre o seletor de respostas prontas. O botão não aparece em notas privadas.

O modal mostra as respostas prontas da conta com o atalho (`/short_code`) e uma prévia em texto simples do início do conteúdo. Ao selecionar uma linha, o `ReplyBox` fecha o modal e envia o conteúdo ao editor. A inserção não cria uma segunda implementação: `WootWriter/Editor.vue#insertCannedResponse` foca o editor e delega para `insertSpecialContent('cannedResponse', content)`, o mesmo caminho usado ao digitar `/short_code`. Isso preserva variáveis, formatação rica, foco, rolagem e analytics já existentes.

## Ordem compartilhada por conta

O modal tem o modo **Organizar**, no qual as linhas podem ser arrastadas pelo handle. Chatwit já inclui `vuedraggable` 4.1.0; nenhuma dependência foi adicionada.

A ordem é da conta, e não do usuário. A migration `20260715000000_add_position_to_canned_responses` adiciona a coluna não nula `position`, preenche os registros existentes por `created_at, id` dentro de cada conta e cria o índice `(account_id, position)`. Novas respostas recebem a próxima posição disponível da conta.

Ao terminar um arrasto, o cliente envia a lista completa de IDs para:

```text
POST /api/v1/accounts/:account_id/canned_responses/reorder
{ "canned_response_ids": [1, 2, 3] }
```

O endpoint aceita somente uma lista completa, sem duplicações, dos IDs da conta atual. Ele atualiza as posições em uma transação e devolve a coleção na ordem autoritativa. Em falha, o modal recarrega a ordem do servidor e mostra um alerta. A listagem sem busca e o menu padrão de `/short_code` usam a mesma ordem persistida. Uma busca digitada no menu mantém a ordenação existente por relevância, usando `position, id` apenas para desempate.

## Escopo

- Implementação exclusiva do dashboard desktop (`ReplyBox` e a barra do compositor).
- Nenhuma alteração no módulo mobile/PWA, no fluxo de criação/edição/exclusão de respostas prontas ou nas permissões existentes.
- A ordenação permanece compartilhada entre todos os agentes da mesma conta.

## Checklist de validação manual

Em uma sessão autenticada do dashboard desktop com pelo menos duas respostas prontas, confirmar:

- O botão do seletor é o primeiro da barra e fica antes do emoji.
- O modal mostra os atalhos e o começo das mensagens.
- Selecionar uma resposta insere o mesmo conteúdo renderizado que `/short_code`.
- O modo Organizar impede a seleção acidental de uma resposta.
- Arrastar, fechar e reabrir o modal preserva a ordem.
- Recarregar a página preserva a ordem.
- O menu de barra (`/`) recebe a mesma ordem padrão.
- Notas privadas não mostram o botão; o layout mobile permanece inalterado.
