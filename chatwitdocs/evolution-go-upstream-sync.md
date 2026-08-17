# Evolution Go: Notas de Sync com Upstream

## Objetivo

O fork Chatwit do `evolution-go` remove a dependência de licença do upstream para que o provider interno suba operacional sem registro externo.

O comportamento é aplicado em:

- `evolution-go/pkg/core/c0.go`

E é mantido de forma reproduzível por:

- `patches/evolution-go/0001-disable-license-gate.patch`
- `patches/evolution-go/0002-disable-external-telemetry.patch`
- `scripts/evolution-go/apply-chatwit-patches.sh`

## O que o patch faz

- Inicializa o runtime como ativo no boot
- Usa `GLOBAL_API_KEY` apenas como chave de autenticação da API local
- Remove chamadas remotas de ativação, heartbeat e deactivate do fluxo Chatwit
- Remove a telemetria HTTP enviada para `log.evolution-api.com`
- Mantém intactas as rotas de instância, QR code, webhook e envio/recebimento
- Mantém o stack Chatwit com `QRCODE_MAX_COUNT=20` para permitir regeneração estável de QR sem deixar a sessão em loop infinito

## Regra importante

`EVOLUTION_GO_GLOBAL_API_KEY` continua obrigatória.

Ela não serve mais para licenciamento no fork Chatwit, mas continua sendo a fonte de verdade para:

- autenticação administrativa do `evolution-go`
- derivação do token de instância usada pelo Chatwit

## Workflow após sync com upstream

1. Atualize o submodule ou a branch do fork `Witroch4/evolution-go`.
2. Rode `scripts/evolution-go/apply-chatwit-patches.sh`.
3. Se o script falhar, o upstream alterou `pkg/core/c0.go` e o patch precisa ser refeito manualmente.
4. Depois de ajustar o patch, atualize este documento e `chatwitdocs/evolution-go-whatsapp.md`.
5. Rebuild a imagem com `./build.sh` ou suba localmente com `./dev.sh`.

## Validação mínima após sync

1. `wget -qO- http://localhost:8080/license/status`
2. Confirmar retorno `{"status":"active", ...}`
3. `wget -qO- --header=\"apikey: $EVOLUTION_GO_GLOBAL_API_KEY\" http://localhost:8080/instance/all`
4. Confirmar que a API não responde mais `503 service not activated`
5. Criar uma inbox `provider: evolution_go` e validar geração de QR
6. Confirmar que o polling do Chatwit continua lendo tanto payload REST Go-style (`Connected`, `LoggedIn`, `Qrcode`, `Code`) quanto webhook payload (`connected`, `loggedIn`, `qrcode`, `code`)

## Motivo de manter patch + script

O submodule ainda acompanha upstream. Sem um patch versionado no repositório principal, um sync futuro pode reintroduzir o gate de licença silenciosamente.

O script foi ligado em:

- `dev.sh`
- `build.sh`

Assim, quando o patch deixar de aplicar, o processo falha cedo em vez de quebrar só em runtime.

## 2026-08-17 — QR code não era gerado (405 client-outdated)

### Sintoma

Na tela de criação de inbox WhatsApp, o pareamento nunca exibia o QR code: a UI
ficava em `Pairing session stopped` e `GET /instance/qr` respondia `400` a cada
polling, com o log `No QR code available yet, waiting a bit more...`.

### Causa

A versão do WhatsApp Web anunciada no handshake estava incoerente com o build
hash enviado junto, e o servidor recusava a conexão com `405 client outdated`.
Nesse caso a whatsmeow entrega `events.ClientOutdated` no lugar de `events.QR`,
então o canal de QR recebia `err-client-outdated` e nada era armazenado.

Dois defeitos somados:

1. `pkg/whatsmeow/service/whatsmeow.go` buscava a versão atual em
   `web.whatsapp.com/sw.js` mas gravava só em `store.DeviceProps.Version`, que é
   apenas o rótulo exibido em "Aparelhos conectados". O handshake seguia usando o
   valor fixo de `store.waVersion`.
2. `store.SetWAVersion` desta versão da `whatsmeow-lib` atualiza `waVersion` e
   `waVersionHash`, mas não o `BaseClientPayload`, montado no init da package com
   a versão fixa. Só chamar `SetWAVersion` produzia um payload incoerente: build
   hash novo, `AppVersion` antigo — recusado do mesmo jeito. O upstream
   (`tulir/whatsmeow`) corrige dentro do próprio `SetWAVersion`; como a
   `whatsmeow-lib` é submódulo de terceiros, o ajuste ficou no nosso código.

### Correção

Em `pkg/whatsmeow/service/whatsmeow.go`, após resolver a versão (por ENV ou pelo
fetch em `sw.js`), chamar `store.SetWAVersion` **e** atribuir
`store.BaseClientPayload.UserAgent.AppVersion`.

### Diagnóstico rápido em produção

```bash
docker service logs chatwoot_app_evolution_go --since 5m 2>&1 \
  | grep -Ei 'Setting whatsapp version|Client outdated|QR code generated'
```

- `QR code generated #1` → pareamento saudável
- `Client outdated (405) ... (client version: X)` → versão recusada pelo WhatsApp

Se o valor publicado em `sw.js` for recusado, dá para fixar uma versão conhecida
sem rebuild, via `WHATSAPP_VERSION_MAJOR` / `WHATSAPP_VERSION_MINOR` /
`WHATSAPP_VERSION_PATCH` no serviço (o branch de ENV passa pelo mesmo caminho
corrigido). Em 2026-08-17 tanto a versão do `sw.js` (`2.3000.1045368834`) quanto
a fixada no upstream (`2.3000.1045305987`) funcionaram, então o stack segue sem
pin, usando o fetch dinâmico.
