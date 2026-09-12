Oq eu quero que tenha uma chave que ativa desativa capitão via chat pra ele começar a responder as perguntas repetitivas no objetivo de receber o pix aí depois desse pix ele desliga sozinho veja como ele pode se alimentar do faq q ele mesmo cria etc um escopo definido pra conduzir o cliente até receber o pix pra prestar um serviço veja como eu posso fazer isso no meu fork de chatwoot o chatwit

# Leitura do Chatwoot/Captain

Analisei o `develop` atual do Chatwoot. A sua ideia é viável, mas a **chave não deve ativar/desativar o Captain na inbox**. Hoje o relacionamento `CaptainInbox` é feito no nível da caixa de entrada, e cada inbox aceita apenas um Captain. Alterar esse vínculo para atender uma conversa acabaria afetando todas as conversas daquela inbox. A solução correta é criar uma **sessão do Captain por conversa**. ([GitHub][1])

O Captain já possui boa parte da infraestrutura necessária:

* Assistentes com documentos, FAQs, cenários, regras de resposta e guardrails.
* Cenários especializados que podem usar ferramentas.
* Ferramentas personalizadas que chamam APIs externas.
* Busca semântica em FAQs.
* Transferência para atendente humano.
* Geração de sugestões de FAQ a partir de conversas resolvidas. ([GitHub][1])

O que ele **não possui pronto** é um ciclo transacional como:

```text
ativar na conversa
    ↓
qualificar o cliente
    ↓
apresentar serviço e preço
    ↓
gerar cobrança Pix
    ↓
aguardar confirmação real
    ↓
desativar a IA automaticamente
    ↓
entregar para humano ou workflow de execução
```

## Um cuidado importante com a licença

O código do Captain fica dentro de `enterprise/`. A licença raiz do Chatwoot declara que essa pasta segue uma licença separada, e a licença Enterprise exige uma assinatura válida para utilização em produção. Portanto:

* **Com licença Enterprise válida:** você pode estender diretamente o Captain no Chatwit.
* **Sem licença Enterprise:** não é recomendável copiar ou transportar o código do Captain para o núcleo MIT. Nesse caso, implemente um agente próprio no Chatwit, usando o `AgentBot` do núcleo aberto ou um serviço externo.

Isso é especialmente importante se o Chatwit for comercializado ou usado em produção. ([GitHub][2])

# Desenho recomendado: “Sessão do Capitão”

A chave exibida na conversa controlaria um registro próprio, por exemplo:

```ruby
Chatwit::AgentSession
```

ou, na versão baseada no Captain Enterprise:

```ruby
Captain::ConversationSession
```

A sessão seria única por conversa e teria um estado explícito.

| Estado             |  IA responde? | Comportamento                          |
| ------------------ | ------------: | -------------------------------------- |
| `inactive`         |           Não | Atendimento humano normal              |
| `qualifying`       |           Sim | Entende qual serviço o cliente precisa |
| `offered`          |           Sim | Apresenta escopo e preço aprovados     |
| `awaiting_payment` | Sim, limitado | Responde dúvidas e acompanha o Pix     |
| `paid`             |           Não | Pix confirmado; IA interrompida        |
| `handoff`          |           Não | Conversa entregue à equipe             |
| `expired`          |           Não | Cobrança expirada                      |
| `cancelled`        |           Não | Capitão desligado manualmente          |

A regra fundamental seria:

```text
O Captain só pode criar uma resposta quando:

sessão ativa
E estado permite IA
E pagamento ainda não foi confirmado
E conversa não está em atendimento humano
```

O Chatwoot já usa o status `pending` para conversas tratadas pelo bot e muda para `open` quando ocorre handoff. Isso pode ser aproveitado, mas eu não usaria apenas `pending/open` como controle da sua operação. Esses status também representam filas de atendimento; misturá-los com pagamento dificultaria auditoria e criaria condições de corrida. ([GitHub][3])

## Modelo de dados

### `chatwit_agent_sessions`

Campos principais:

```text
id
account_id
conversation_id                unique
assistant_id                   opcional
scenario_id                    opcional
status
objective                      "collect_pix"
service_code
amount_cents
currency                       "BRL"
payment_provider
payment_reference
activated_by_id
deactivated_by_id
activated_at
expires_at
paid_at
deactivated_at
deactivation_reason
context                        jsonb
lock_version
created_at
updated_at
```

O campo `context` guardaria dados estruturados da venda:

```json
{
  "customer_need": "segunda via de documento",
  "service_code": "DOC_002",
  "required_fields": {
    "city": "Fortaleza",
    "document_type": "..."
  },
  "accepted_offer_version": 4
}
```

Não use `custom_attributes` da conversa como única fonte da verdade. Eles podem ser usados para exibição e filtros, mas pagamento e ativação precisam de tabela própria, índices, auditoria e bloqueio transacional.

### `chatwit_payment_charges`

```text
id
agent_session_id
provider
external_id                    unique
provider_event_id
status
amount_cents
currency
payment_code
expires_at
paid_at
cancelled_at
created_at
updated_at
```

Também é conveniente uma tabela de eventos de webhook:

```text
chatwit_payment_events

provider_event_id              unique
payment_charge_id
verified
payload_digest
received_at
processed_at
processing_error
```

Isso impede que o mesmo webhook gere duas confirmações ou desligue o bot duas vezes.

# Funcionamento da chave na conversa

Na tela da conversa, eu colocaria uma ação como:

```text
[ Capitão desta conversa: DESLIGADO ]
```

Depois de ativado:

```text
[ Capitão: QUALIFICANDO ]
```

E durante a cobrança:

```text
[ Capitão: AGUARDANDO PIX ]
```

Após a confirmação:

```text
[ Capitão: PIX CONFIRMADO — DESLIGADO ]
```

O local provável de integração no frontend é o conjunto de componentes da tela de conversa, como `ConversationAction.vue` ou o painel lateral. O Chatwoot usa Vue no dashboard e já mantém os controles da conversa nessa área. ([GitHub][4])

### Ativação

Ao clicar em ativar:

1. Cria ou reativa a sessão.
2. Registra quem ativou.
3. Seleciona o cenário de venda.
4. Coloca a conversa em modo bot, quando aplicável.
5. Enfileira uma mensagem inicial opcional.
6. Atualiza a interface em tempo real.

Endpoint sugerido:

```http
POST /api/v1/accounts/:account_id/conversations/:display_id/sales_agent_session
```

Payload:

```json
{
  "scenario_id": 12,
  "service_code": "CONSULTORIA_INICIAL",
  "objective": "collect_pix"
}
```

### Desativação manual

```http
DELETE /api/v1/accounts/:account_id/conversations/:display_id/sales_agent_session
```

Ao desativar:

* Marca a sessão como `cancelled`.
* Registra agente e motivo.
* Impede novos jobs.
* Transfere ou mantém a conversa com o humano.
* Não apaga histórico nem cobrança.

# O escopo que conduz até o Pix

Eu trataria esse fluxo como um **playbook de venda**, e não apenas como um prompt grande.

## Etapa 1 — Identificação do serviço

O Captain pode:

* Responder dúvidas repetitivas.
* Detectar qual serviço o cliente pretende contratar.
* Fazer perguntas previstas no catálogo.
* Recusar solicitações fora do escopo.
* Transferir para humano em casos excepcionais.

Ele não deve inventar um novo serviço com base apenas na conversa.

## Etapa 2 — Coleta de dados mínimos

Cada serviço teria um esquema de campos obrigatório:

```yaml
service_code: CONSULTORIA_INICIAL
required_fields:
  - customer_name
  - company_name
  - requested_topic
optional_fields:
  - preferred_date
```

O agente pergunta apenas os campos ainda ausentes.

## Etapa 3 — Cotação determinada pelo servidor

O modelo não deveria calcular ou escolher livremente o preço.

Ele chama uma ferramenta:

```text
quote_service
```

Entrada:

```json
{
  "service_code": "CONSULTORIA_INICIAL",
  "conversation_id": 1234
}
```

Resposta:

```json
{
  "offer_id": "offer_983",
  "offer_version": 4,
  "description": "Consultoria inicial de até 60 minutos",
  "amount_cents": 25000,
  "currency": "BRL",
  "expires_at": "2026-07-16T18:00:00-03:00"
}
```

Assim o LLM não pode dar desconto, trocar moeda, prometer algo não autorizado ou usar um preço antigo de FAQ.

## Etapa 4 — Consentimento

Antes de gerar a cobrança, o agente resume:

* O serviço.
* O que está incluído.
* O que não está incluído.
* O valor.
* O prazo ou condições de atendimento.
* A validade da oferta.

Só depois de uma confirmação clara ele pode chamar:

```text
create_pix_charge
```

## Etapa 5 — Criação do Pix

Prefira cobrança Pix dinâmica, com um identificador exclusivo da transação. Uma chave Pix estática dificulta saber qual conversa fez o pagamento e torna o desligamento automático pouco confiável.

A ferramenta de geração precisa ser idempotente:

```text
uma sessão + uma oferta + uma tentativa = uma cobrança
```

Mesmo que o Captain chame a ferramenta novamente, o backend deve devolver a cobrança já existente em vez de criar outra.

## Etapa 6 — Aguardando pagamento

Em `awaiting_payment`, o agente pode responder somente sobre:

* Como pagar.
* Prazo de validade.
* Valor.
* Escopo contratado.
* Problemas no código Pix.
* Situação atual da cobrança.

Ele não deve voltar a negociar nem gerar outro valor sem cancelar formalmente a cobrança anterior.

## Etapa 7 — Confirmação verdadeira

A frase do cliente “já paguei” **não pode marcar a cobrança como paga**.

Ela pode fazer o agente consultar:

```text
check_pix_status
```

Mas a fonte de verdade deve ser:

* Webhook assinado do provedor de pagamento; ou
* Consulta autenticada ao provedor.

No webhook, valide:

1. Assinatura ou credencial do provedor.
2. Identificador da cobrança.
3. Conta recebedora.
4. Valor.
5. Moeda.
6. Status final da transação.
7. Duplicidade do evento.

Depois, dentro de uma transação com lock:

```text
marcar cobrança como paga
marcar sessão como paid
desativar a IA
registrar nota privada
enviar uma única confirmação determinística
atribuir a conversa à equipe ou iniciar entrega
```

A mensagem de confirmação não deve ser gerada livremente pelo LLM. Use um template como:

> Pagamento confirmado. Seu atendimento foi encaminhado para a etapa de execução do serviço.

# Evitando uma resposta atrasada depois do pagamento

Há uma condição de corrida importante:

```text
10:00:00 — Captain começa a gerar uma resposta
10:00:02 — webhook confirma o Pix
10:00:04 — resposta antiga fica pronta
```

Sem uma segunda validação, o Captain pode responder mesmo já estando desligado.

Por isso são necessárias duas verificações:

1. Antes de iniciar a geração.
2. Imediatamente antes de gravar/enviar a mensagem.

Conceitualmente:

```ruby
return unless session.automation_allowed?

result = generate_response

session.reload
return unless session.automation_allowed?

create_outgoing_message(result)
```

No Captain atual, o ponto central para esse bloqueio é o `Captain::Conversation::ResponseBuilderJob`, que constrói e publica a resposta. ([GitHub][5])

# Como ele se alimentaria das FAQs que cria

O Captain já faz algo próximo disso. Quando uma conversa com participação humana é resolvida, um listener pode chamar o serviço de geração de FAQ. Ele extrai perguntas e respostas, faz deduplicação semântica e salva novas entradas como **pendentes**. A busca usada pelo Captain considera FAQs aprovadas, não qualquer sugestão recém-gerada. ([GitHub][6])

Esse fluxo é adequado e eu manteria a aprovação:

```text
conversa humana resolvida
       ↓
geração de sugestões
       ↓
remoção de duplicadas
       ↓
status pending
       ↓
revisão por administrador
       ↓
status approved
       ↓
disponível para o Captain
```

Não recomendo aprovação automática irrestrita, porque uma conversa pode conter:

* Preço negociado para um cliente específico.
* Informação pessoal.
* Exceção comercial.
* Informação incorreta dada por um atendente.
* Dados de cobrança.
* Discussão de estorno ou disputa.
* Uma condição que já expirou.

## Metadados adicionais para a FAQ do Chatwit

Eu adicionaria:

```text
source_type
source_id
service_code
scenario_id
language
confidence
approved_by_id
approved_at
last_verified_at
usage_count
successful_resolution_count
```

E estas regras:

* FAQ de preço não é fonte de verdade; preço vem de `quote_service`.
* FAQ pendente nunca responde ao cliente.
* Conversas totalmente feitas pela IA não geram automaticamente “novos fatos”.
* Dados pessoais e identificadores de pagamento são removidos.
* Perguntas quase iguais são agrupadas.
* FAQs antigas passam por revisão periódica.
* O administrador consegue abrir a conversa de origem.

Os documentos do Captain também podem gerar FAQs a partir de URLs e PDFs, permitindo alimentar a base com conteúdo oficial antes de começar a aprender com atendimentos. ([GitHub][7])

# Ferramentas do cenário

Para o cenário **“Venda de serviço via Pix”**, eu permitiria somente:

```text
faq_lookup
quote_service
create_pix_charge
check_pix_status
cancel_pix_charge
add_private_note
handoff
```

E colocaria estas proibições explícitas:

```text
não inventar preço
não oferecer desconto sem ferramenta
não marcar pagamento com base no texto do cliente
não modificar o escopo depois do aceite
não gerar cobrança sem consentimento
não revelar credenciais ou dados internos
não continuar respondendo depois de payment.confirmed
```

O Captain atual suporta cenários e ferramentas personalizadas GET/POST para conversar com APIs externas. Essas chamadas devem ir para uma API interna sua — por exemplo, `payments.chatwit.internal` — e não diretamente do LLM para o provedor de pagamento. Assim, as credenciais e regras de validação ficam fora do contexto do modelo. ([GitHub][8])

# Três maneiras de implementar

## 1. Estender o Captain Enterprise

**Recomendado quando o Chatwit possui licença Enterprise válida.**

Você reutiliza:

* Assistente.
* Cenários.
* Guardrails.
* FAQ e embeddings.
* Documentos.
* Ferramentas personalizadas.
* Handoff.
* Interface administrativa.

Principais alterações:

```text
enterprise/app/models/captain/conversation_session.rb
enterprise/app/services/captain/conversation_sessions/activate_service.rb
enterprise/app/services/captain/conversation_sessions/deactivate_service.rb
enterprise/app/jobs/captain/conversation/response_builder_job.rb
enterprise/app/services/captain/assistant/agent_runner_service.rb
enterprise/lib/captain/tools/create_pix_charge_tool.rb
enterprise/lib/captain/tools/check_pix_status_tool.rb
config/agents/tools.yml
```

Além disso:

```text
app/controllers/webhooks/chatwit/pix_controller.rb
app/services/chatwit/payments/*
app/jobs/chatwit/payments/process_webhook_job.rb
```

Vantagem: integração mais profunda e menor duplicação funcional.

Desvantagem: dependência do código Enterprise e maior cuidado nos merges com o upstream.

## 2. AgentBot externo como primeiro produto

**Recomendado como MVP sem licença Enterprise.**

O núcleo aberto do Chatwoot já possui `AgentBot`, entrega eventos para um webhook e permite atribuição de bot às conversas. Isso possibilita manter o raciocínio, estado, pagamento e FAQ em um serviço separado, enquanto o Chatwit continua sendo a interface de atendimento. ([GitHub][9])

Arquitetura:

```text
Chatwit
  ├─ conversa e mensagens
  ├─ botão ativar/desativar
  └─ eventos webhook
          ↓
Chatwit Sales Agent
  ├─ estado da sessão
  ├─ LLM
  ├─ RAG/FAQ
  ├─ catálogo de serviços
  └─ integração Pix
          ↑
provedor de pagamento
```

Vantagens:

* Poucas alterações profundas no Chatwoot.
* Serviço de pagamento isolado.
* Mais fácil trocar o modelo ou o provedor.
* Menor conflito ao atualizar o fork.

Desvantagens:

* Mais uma aplicação para operar.
* Necessidade de sincronização por webhooks.
* Administração do FAQ inicialmente menos integrada.

## 3. Agente nativo independente no núcleo do Chatwit

Você constrói uma implementação própria, sem copiar o Captain Enterprise:

```text
app/models/chatwit/agent_session.rb
app/models/chatwit/knowledge_entry.rb
app/models/chatwit/payment_charge.rb
app/listeners/chatwit_agent_listener.rb
app/services/chatwit/agent/*
app/services/chatwit/knowledge/*
app/services/chatwit/payments/*
```

Vantagens:

* Totalmente integrado ao Chatwit.
* Controle integral do produto.
* Sem dependência arquitetural do Captain.

Desvantagens:

* Mais trabalho para implementar RAG, embeddings, avaliação, ferramentas e gestão de prompts.
* Maior responsabilidade de manutenção.

## Minha recomendação

* **Com licença Enterprise:** opção 1.
* **Sem licença Enterprise e buscando validar o produto:** opção 2.
* **Depois de validar volume e conversão:** migrar gradualmente da opção 2 para a opção 3, caso faça sentido tornar tudo nativo.

# Escopo de um MVP seguro

## Incluído

* Chave por conversa.
* Ativação e desativação manual.
* Um cenário de venda.
* Catálogo com preços fixados pelo servidor.
* Perguntas de qualificação estruturadas.
* Uma integração de cobrança Pix.
* Confirmação por webhook.
* Desativação automática.
* Entrega para humano.
* FAQ manual e sugestões pendentes.
* Registro de auditoria.
* Métricas básicas.

## Fora do primeiro escopo

* Negociação autônoma de descontos.
* Parcelamento.
* Estorno e chargeback automáticos.
* Preços produzidos pelo LLM.
* Aprovação automática de toda FAQ.
* Vários provedores de pagamento simultâneos.
* Execução autônoma de serviços complexos.
* Alteração de cobrança somente por texto do cliente.

# Critérios de aceite

A implementação estará correta quando:

1. Ativar o Captain em uma conversa não ativa nas demais.
2. Desativá-lo impede novas respostas.
3. Um job já iniciado não publica resposta depois da desativação.
4. “Eu já paguei” não altera o status financeiro.
5. Um webhook válido desativa o agente e envia uma única confirmação.
6. Webhook repetido não duplica mensagens.
7. Valor ou identificador divergente não confirma a sessão.
8. O atendente pode assumir a conversa a qualquer momento.
9. Somente FAQs aprovadas são utilizadas.
10. O modelo não inventa preço nem desconto.
11. Todas as mudanças de estado têm ator, data e motivo.
12. Uma falha no provedor mantém a conversa segura e disponível para atendimento humano.

O mapeamento acima foi feito sobre o upstream do Chatwoot; como o endereço e o branch do repositório do Chatwit não vieram na mensagem, ainda não identifiquei eventuais alterações próprias do seu fork.

**A decisão funcional que falta para fechar o desenho:** depois que o Pix for confirmado, o Chatwit deve **(A)** desligar a IA, manter a conversa aberta e atribuí-la à equipe que executará o serviço; **(B)** resolver a conversa automaticamente; ou **(C)** desligar a IA e disparar um workflow externo de entrega? Minha recomendação inicial é **A**, com possibilidade de o atendente iniciar o workflow de execução.

[1]: https://github.com/chatwoot/chatwoot/blob/develop/enterprise/app/models/captain/assistant.rb "https://github.com/chatwoot/chatwoot/blob/develop/enterprise/app/models/captain/assistant.rb"
[2]: https://raw.githubusercontent.com/chatwoot/chatwoot/develop/enterprise/LICENSE "https://raw.githubusercontent.com/chatwoot/chatwoot/develop/enterprise/LICENSE"
[3]: https://raw.githubusercontent.com/chatwoot/chatwoot/develop/app/models/conversation.rb "https://raw.githubusercontent.com/chatwoot/chatwoot/develop/app/models/conversation.rb"
[4]: https://github.com/chatwoot/chatwoot/tree/develop/app/javascript/dashboard/routes/dashboard/conversation "https://github.com/chatwoot/chatwoot/tree/develop/app/javascript/dashboard/routes/dashboard/conversation"
[5]: https://github.com/chatwoot/chatwoot/blob/develop/enterprise/app/jobs/captain/conversation/response_builder_job.rb "https://github.com/chatwoot/chatwoot/blob/develop/enterprise/app/jobs/captain/conversation/response_builder_job.rb"
[6]: https://raw.githubusercontent.com/chatwoot/chatwoot/develop/enterprise/app/listeners/captain_listener.rb "https://raw.githubusercontent.com/chatwoot/chatwoot/develop/enterprise/app/listeners/captain_listener.rb"
[7]: https://raw.githubusercontent.com/chatwoot/chatwoot/develop/enterprise/app/models/captain/document.rb "https://raw.githubusercontent.com/chatwoot/chatwoot/develop/enterprise/app/models/captain/document.rb"
[8]: https://raw.githubusercontent.com/chatwoot/chatwoot/develop/enterprise/app/models/captain/scenario.rb "https://raw.githubusercontent.com/chatwoot/chatwoot/develop/enterprise/app/models/captain/scenario.rb"
[9]: https://raw.githubusercontent.com/chatwoot/chatwoot/develop/app/models/agent_bot.rb "https://raw.githubusercontent.com/chatwoot/chatwoot/develop/app/models/agent_bot.rb"


Uma IA faz o primeiro atendimento e ela entrega com pix pago porém antes de pagar alguns clientes tem medo do link que é enorme eu crie formas de gerar link dentro de CTA pra ficar mais bonito o que acontece após receber desse agente vou mandar com alguma tag pra informa algo como olá eu sou o primeiro agente de IA esse cliente é do fluxo do Recurso ADM da OAB aí o capitão acorda sozinho nessa conversa ler todas mensagens vê se o cliente já pagou o pix inicial o pix da análise não pagou? Ver se o cliente tem dúvidas ou teve problemas às vezes medo do link da infinitpay que é muito grade oferece via tools um link CTA pra ele fala se na conseguir pagar me fala que mando no CNPJ etc é isso ele vai fazer o segundo atendimento se ver que já deu certo ou que o usuário não tem nada de dúvida ele só dorme denvo e espera ser ativo manulmte. Era algo do tipo 



Sim — agora ficou claro. Você não quer que o Captain faça o primeiro atendimento nem fique permanentemente respondendo. Ele será um **segundo agente especializado em recuperação/assistência de pagamento**, que acorda em uma conversa específica, revisa o que aconteceu e só fala quando existe algo útil a resolver.

## O papel de cada IA

### Primeiro agente: atendimento e oferta

O primeiro agente:

1. Identifica que o cliente está no fluxo **Recurso Administrativo da OAB**.
2. Explica o serviço e o valor da análise.
3. Gera ou envia a cobrança inicial.
4. Envia o link da InfinitePay, preferencialmente no CTA que você criou.
5. Entrega a conversa ao segundo agente com dados estruturados.
6. Solicita que o Captain faça uma revisão.

### Segundo agente: Captain de pagamento

O Captain:

1. Acorda somente naquela conversa.
2. Lê o histórico público da conversa.
3. Recebe o contexto estruturado do primeiro agente.
4. Consulta no sistema se o Pix da análise está pago.
5. Identifica se o cliente demonstrou medo, dúvida ou problema para pagar.
6. Responde somente quando necessário.
7. Usa ferramentas para enviar CTA, Pix por CNPJ ou consultar pagamento.
8. Dorme quando:

   * O Pix foi confirmado;
   * Não há nenhuma dúvida;
   * A dúvida foi resolvida;
   * O caso precisa de atendimento humano.

Isso combina com a estrutura do Captain atual: ele já possui cenários especializados, ferramentas por cenário, FAQ e acesso ao contexto da conversa. O runner atual também recebe labels, atributos personalizados e histórico da conversa. ([GitHub][1])

# A tag deve acordá-lo, mas não guardar todo o contexto

Eu não colocaria algo como:

> Olá, eu sou o primeiro agente de IA, esse cliente é do fluxo Recurso ADM da OAB...

dentro de uma mensagem pública. O cliente não precisa ver essa conversa entre agentes.

Também não colocaria todas essas informações no nome de uma tag. A tag deve servir apenas como **sinal visual e gatilho**.

Por exemplo:

```text
fluxo:recurso-adm-oab
captain:revisar-pagamento
```

O contexto verdadeiro deve ficar estruturado em uma sessão:

```json
{
  "source_agent": "primeiro_atendimento",
  "flow_key": "recurso_adm_oab",
  "objective": "confirmar_pagamento_analise",
  "payment_provider": "infinitepay",
  "charge_id": "charge_983721",
  "service_code": "analise_recurso_oab",
  "customer_stage": "link_enviado",
  "handoff_reason": "revisar_pagamento_e_duvidas"
}
```

As labels do Chatwoot podem ser adicionadas às conversas e servem bem para identificação visual e filtros. Porém, o estado financeiro e o contexto do handoff devem ficar em uma tabela própria, porque uma label pode ser removida, adicionada novamente ou alterada manualmente. ([GitHub][2])

## Handoff recomendado

O primeiro agente chamaria uma ferramenta interna:

```text
wake_payment_captain
```

Exemplo de entrada:

```json
{
  "conversation_id": 1532,
  "flow_key": "recurso_adm_oab",
  "charge_id": "charge_983721",
  "service_code": "analise_recurso_oab",
  "reason": "second_payment_review",
  "idempotency_key": "conversation-1532-analysis-payment-v1"
}
```

Essa ferramenta:

```text
cria ou atualiza a sessão do Captain
        ↓
adiciona a tag fluxo:recurso-adm-oab
        ↓
registra o identificador da cobrança
        ↓
cria um evento de despertar
        ↓
enfileira a revisão da conversa
```

Para os atendentes humanos, ela também pode inserir uma nota privada legível:

```text
🤖 Handoff entre agentes

Fluxo: Recurso Administrativo da OAB
Objetivo: verificar pagamento da análise
Cobrança: charge_983721
Situação informada pelo primeiro agente: link enviado
Captain: revisão automática solicitada
```

A nota privada seria apenas para auditoria humana. O contexto da IA viria da sessão estruturada. Isso é importante porque o construtor V1 do Captain filtra mensagens privadas e envia ao modelo apenas mensagens públicas de entrada e saída. ([GitHub][3])

# Não misturar “Captain acordado” com “Pix pago”

O melhor desenho usa dois estados independentes.

## Estado do agente

```text
sleeping
reviewing
assisting
waiting_customer
needs_human
```

## Estado do pagamento

```text
unknown
pending
paid
expired
cancelled
provider_error
```

Assim você pode ter situações como:

```text
Captain: sleeping
Pagamento: pending
```

Isso significa: o cliente ainda não pagou, mas não apresentou dúvida; portanto, o Captain não precisa ficar falando.

Ou:

```text
Captain: assisting
Pagamento: pending
```

Isso significa: o pagamento ainda não ocorreu e o cliente está com medo do link, não conseguiu pagar ou pediu outra forma.

# O ciclo exato do segundo atendimento

```text
Primeiro agente solicita handoff
              ↓
Captain entra em REVIEWING
              ↓
Consulta o pagamento pela charge_id
              ↓
Analisa a última necessidade do cliente
              ↓
Política decide se deve responder
```

## Caso 1 — O Pix já foi pago

O Captain:

* Confirma por ferramenta/API, não pelo texto da conversa.
* Adiciona a label `pix:analise-pago`.
* Atualiza a sessão.
* Não oferece outro link.
* Dorme imediatamente.
* Opcionalmente envia uma confirmação fixa, sem LLM.

Exemplo:

> Pagamento da análise confirmado. Agora seu atendimento seguirá para a próxima etapa.

Essa mensagem deve ser opcional e determinística. O modelo não precisa redigi-la toda vez.

## Caso 2 — Não pagou, mas não há dúvida

Exemplo de conversa:

```text
Agente: Enviei o link para pagamento.
Cliente: Certo, vou verificar.
```

O Captain verifica:

```text
pagamento = pending
dúvida = nenhuma
problema = nenhum
```

Resultado:

```text
não envia mensagem
registra revisão concluída
volta para sleeping
```

Isso evita que dois agentes pressionem o cliente ou repitam informações.

## Caso 3 — Medo do link grande

Exemplo:

```text
Cliente: Esse link é muito estranho.
Cliente: Por que ele é tão grande?
Cliente: Tenho medo de clicar.
```

O Captain identifica:

```text
intent = link_safety_concern
pagamento = pending
```

Ele responde com uma explicação curta e chama uma ferramenta:

```text
send_payment_cta
```

Exemplo de resposta:

> Entendo sua preocupação. Esse é o endereço de pagamento gerado para a sua cobrança. Para ficar mais simples, deixei o acesso no botão abaixo.

E a ferramenta envia:

```text
┌──────────────────────────────────┐
│ Pagamento da análise             │
│                                  │
│ Valor: R$ XXX,XX                 │
│ Pagamento processado pela        │
│ InfinitePay                      │
│                                  │
│ [ Pagar análise com Pix ]        │
└──────────────────────────────────┘
```

O ponto importante é: **a ferramenta envia o CTA diretamente**. Ela não deveria simplesmente devolver o link enorme para o LLM.

A ferramenta recebe algo seguro, como:

```json
{
  "conversation_id": 1532,
  "charge_id": "charge_983721",
  "cta_variant": "analysis_payment"
}
```

O servidor busca o link verdadeiro a partir da cobrança e monta o conteúdo estruturado. Assim o modelo:

* Não inventa links;
* Não troca o link de um cliente pelo de outro;
* Não revela o URL enorme no texto;
* Não consegue inserir um endereço arbitrário;
* Não precisa conhecer credenciais da InfinitePay.

O Captain atual suporta ferramentas próprias e ferramentas personalizadas com endpoint HTTP, parâmetros e autenticação. Também permite limitar as ferramentas disponíveis em cada cenário. ([GitHub][4])

## Caso 4 — Cliente quer pagar pelo CNPJ

Exemplo:

```text
Cliente: Tem como mandar o Pix pelo CNPJ?
Cliente: Prefiro pagar direto pela chave.
```

O Captain chama:

```text
send_official_pix_cnpj
```

A ferramenta busca no servidor:

```json
{
  "legal_name": "NOME EMPRESARIAL",
  "pix_key_type": "cnpj",
  "pix_key_masked": "12.***.***/****-90",
  "amount_cents": 0,
  "payment_reference": "..."
}
```

E envia uma mensagem padronizada:

> Também é possível pagar pelo Pix oficial da empresa. Confira com atenção o nome do recebedor antes de confirmar.

O CNPJ nunca deve ficar escrito diretamente no prompt do agente. Ele deve vir da configuração do servidor.

Se esse pagamento for feito por uma chave estática, pode ser mais difícil relacioná-lo automaticamente à conversa. Portanto, o sistema deve manter o pagamento como `pending` até ocorrer uma destas condições:

* Confirmação pela API bancária;
* Confirmação pelo provedor;
* Conciliação por identificador;
* Confirmação manual por um atendente autorizado.

Uma foto ou frase do cliente dizendo “paguei” não deve alterar o status financeiro.

## Caso 5 — Link expirado ou com erro

O Captain chama:

```text
check_payment_charge
```

A ferramenta devolve:

```json
{
  "status": "expired",
  "can_regenerate": true
}
```

Depois ele chama:

```text
regenerate_payment_cta
```

O servidor cancela ou invalida o link anterior, gera uma cobrança nova e envia o novo CTA.

O modelo não deve decidir sozinho que é necessário gerar uma segunda cobrança.

## Caso 6 — Situação confusa

Exemplos:

* O cliente afirma que pagou, mas o provedor não localizou.
* O valor pago é diferente.
* O nome do pagador é de terceiro.
* Existem duas cobranças.
* A cobrança pertence a outra conversa.
* O provedor está indisponível.

Resultado:

```text
Captain não confirma o pagamento
adiciona nota privada
marca needs_human
dorme
```

Exemplo de mensagem:

> Ainda não consegui confirmar automaticamente esse pagamento. Vou deixar a situação sinalizada para verificação.

# O Captain deve tomar uma decisão estruturada

Eu evitaria pedir ao LLM:

> Leia tudo e decida livremente o que fazer.

O processo mais seguro é separar em três partes.

## 1. Ferramenta determina o pagamento

```json
{
  "payment_status": "pending",
  "charge_id": "charge_983721"
}
```

## 2. IA classifica somente a necessidade do cliente

```json
{
  "customer_intent": "link_safety_concern",
  "has_open_question": true,
  "customer_needs_reply": true,
  "confidence": 0.94
}
```

Possíveis intenções:

```text
no_question
link_safety_concern
payment_link_not_opening
request_pix_cnpj
claims_payment_completed
payment_expired
asks_about_service
asks_about_next_steps
unrelated_question
needs_human
```

## 3. Código aplica a política

```ruby
if payment.paid?
  mark_paid_and_sleep
elsif intent.no_question?
  sleep_without_reply
elsif intent.link_safety_concern?
  answer_and_send_cta
elsif intent.request_pix_cnpj?
  send_official_pix_key
elsif intent.claims_payment_completed?
  verify_payment_again
else
  handoff_or_answer_faq
end
```

O pagamento vem da API. A intenção vem da IA. A decisão final vem do código.

# Como encaixar isso no Captain atual

Eu criaria um job separado:

```text
Captain::Conversation::PaymentReviewJob
```

Em vez de tentar usar diretamente o fluxo comum do `ResponseBuilderJob`.

Isso é relevante porque o `ResponseBuilderJob` atual só continua quando a conversa está em `pending` e, quando recebe uma resposta normal, cria uma mensagem de saída. Para uma revisão que pode terminar silenciosamente em `NO_ACTION`, é melhor colocar um orquestrador antes dele. ([GitHub][3])

Fluxo sugerido:

```ruby
class Captain::Conversation::PaymentReviewJob < ApplicationJob
  def perform(session_id, wake_event_id)
    session = Captain::ConversationSession.find(session_id)

    session.with_lock do
      return unless session.can_process_wake_event?(wake_event_id)

      session.start_review!
    end

    payment = PaymentStatusService.new(session).perform
    intent = PaymentIntentClassifier.new(session).perform
    decision = PaymentDecisionPolicy.new(
      session: session,
      payment: payment,
      intent: intent
    ).perform

    PaymentDecisionExecutor.new(
      session: session,
      decision: decision
    ).perform
  end
end
```

Somente o executor decide se deve chamar o Captain para redigir uma resposta.

## Assistente dedicado

Eu criaria um Assistant específico:

```text
Nome: Captain — Suporte ao pagamento
```

Cenário:

```text
Recurso ADM OAB — Pagamento da análise
```

Ferramentas permitidas:

```text
check_payment_charge
send_payment_cta
send_official_pix_cnpj
regenerate_payment_cta
faq_lookup
add_private_note
handoff
```

Ferramentas que ele não deveria possuir:

```text
alterar preço
conceder desconto
cancelar serviço
confirmar pagamento manualmente
alterar dados bancários
criar link arbitrário
```

# Onde guardar a sessão

Modelo recomendado:

```text
captain_conversation_sessions
```

Campos principais:

```text
id
account_id
conversation_id
assistant_id
scenario_id
flow_key
agent_mode
payment_status
payment_provider
payment_reference
wake_reason
handoff_context
last_reviewed_message_id
last_wake_event_id
activated_at
last_reviewed_at
slept_at
paid_at
created_at
updated_at
```

Exemplo:

```json
{
  "flow_key": "recurso_adm_oab",
  "agent_mode": "sleeping",
  "payment_status": "pending",
  "payment_provider": "infinitepay",
  "payment_reference": "charge_983721",
  "handoff_context": {
    "service_code": "analise_recurso_oab",
    "source_agent": "primeiro_atendimento",
    "customer_stage": "link_enviado"
  }
}
```

# Acordar por tag ou por ferramenta

## Melhor opção: ferramenta/evento explícito

```text
primeiro agente
      ↓
wake_payment_captain
      ↓
sessão + label + job
```

É a opção mais confiável.

## Alternativa: tag como gatilho

Caso o primeiro agente só consiga adicionar labels:

```text
captain:revisar-pagamento
```

Um listener detecta a inclusão e executa:

```text
criar wake_event
remover captain:revisar-pagamento
manter fluxo:recurso-adm-oab
enfileirar PaymentReviewJob
```

A tag de gatilho deve ser removida depois de consumida para poder ser adicionada novamente.

É necessário usar uma chave de idempotência para impedir que sincronizações ou atualizações repetidas acordem o Captain duas vezes:

```text
conversation_id + label_change_event_id
```

# Como ele lê a conversa sem desperdiçar contexto

Embora o Captain possa receber o histórico, não é ideal reenviar uma conversa enorme integralmente a cada despertar.

Eu usaria:

```text
resumo anterior da conversa
+
handoff_context do primeiro agente
+
últimas 20–30 mensagens públicas relevantes
+
última mensagem do cliente
+
estado atual do pagamento
```

O runner V2 atual já monta estado com informações da conversa, labels, custom attributes e additional attributes, além do histórico preparado para o agente. Isso permite acrescentar `captain_session` ao estado sem reconstruir todo o Captain. ([GitHub][5])

Algo como:

```ruby
state[:captain_session] = {
  flow_key: session.flow_key,
  agent_mode: session.agent_mode,
  payment_status: payment.status,
  service_code: session.handoff_context['service_code'],
  allowed_objective: 'resolve_analysis_payment_questions'
}
```

# FAQ criada pelo próprio fluxo

O Captain pode aprender as perguntas recorrentes:

```text
Por que o link é tão grande?
É seguro clicar?
Posso pagar por CNPJ?
O nome do recebedor está correto?
O link expirou, e agora?
Quanto tempo demora para confirmar?
O que acontece depois do pagamento?
```

Mas existem dois tipos de conhecimento.

## Pode virar FAQ

```text
explicação sobre o processo
como usar o CTA
como identificar o recebedor
o que acontece depois do pagamento
como solicitar uma nova cobrança
prazos gerais aprovados
```

## Nunca deve vir da FAQ

```text
status atual do pagamento
link individual da cobrança
CNPJ/chave Pix sem consulta ao servidor
valor individual
identificador da cobrança
confirmação de pagamento
```

Essas informações devem sempre vir das ferramentas.

O Captain atual já possui um listener que, quando habilitado, gera e deduplica sugestões de FAQ a partir de conversas resolvidas. Para o seu fluxo, eu manteria essas sugestões pendentes para revisão, em vez de permitir que uma conversa isolada altere imediatamente o que a IA diz aos próximos clientes. ([GitHub][6])

Também registraria:

```text
intent_key
answer_variant
cta_used
payment_completed_after_answer
human_intervention_required
source_conversation_id
```

Assim você consegue descobrir, por exemplo:

```text
Pergunta: medo do link
Resposta A: somente explicação
Conversão: 22%

Resposta B: explicação + CTA
Conversão: 61%
```

# Comportamento final recomendado

O fluxo completo ficaria:

```text
PRIMEIRO AGENTE
Atende → apresenta análise → cria cobrança → envia CTA
                         ↓
         chama wake_payment_captain
                         ↓
CAPTAIN
lê contexto → consulta Pix → identifica dúvida
                         ↓
        ┌────────────────┼─────────────────┐
        │                │                 │
     já pagou       não tem dúvida    tem dúvida/problema
        │                │                 │
marca pago          não responde       responde e usa tool
e dorme             e dorme            CTA/CNPJ/status
                                           │
                                  dúvida resolvida ou Pix pago
                                           │
                                         dorme
```

Portanto, sim: é exatamente um **Captain de segundo atendimento, acionado por evento, silencioso por padrão e especializado em remover barreiras ao pagamento**. Ele não fica perseguindo o cliente, não repete o primeiro agente e não considera a frase “já paguei” como confirmação.

A regra que falta validar é esta: **depois que o Captain responder à dúvida e enviar o CTA, ele permanece acordado apenas durante essa sequência de suporte, dormindo quando o Pix for confirmado ou quando a dúvida terminar; quando acordar e não encontrar dúvida, não envia absolutamente nada. É esse o comportamento desejado?**

[1]: https://raw.githubusercontent.com/chatwoot/chatwoot/develop/enterprise/app/models/captain/assistant.rb "raw.githubusercontent.com"
[2]: https://github.com/chatwoot/chatwoot/blob/develop/app/controllers/api/v1/accounts/conversations/labels_controller.rb "chatwoot/app/controllers/api/v1/accounts/conversations/labels_controller.rb at develop · chatwoot/chatwoot · GitHub"
[3]: https://raw.githubusercontent.com/chatwoot/chatwoot/develop/enterprise/app/jobs/captain/conversation/response_builder_job.rb "raw.githubusercontent.com"
[4]: https://raw.githubusercontent.com/chatwoot/chatwoot/develop/enterprise/app/models/captain/custom_tool.rb "raw.githubusercontent.com"
[5]: https://raw.githubusercontent.com/chatwoot/chatwoot/develop/enterprise/app/services/captain/assistant/agent_runner_service.rb "raw.githubusercontent.com"
[6]: https://raw.githubusercontent.com/chatwoot/chatwoot/develop/enterprise/app/listeners/captain_listener.rb "raw.githubusercontent.com"
