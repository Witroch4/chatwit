# Exposes the model catalog for the Captain phase-2 config select.
#
# Canonical contract (CLAUDE.md): platform-litellm is the authority and
# platform-api /api/v1/llm/models is the ONLY listing contract. The Chatwit side
# lists solely through Chatwit::LlmProxy.catalog_models — never a local catalog,
# never a direct LiteLLM call. Central unavailable/empty degrades to
# { models: [], source: "unavailable" } with a stable 200 and never leaks the
# internal key or URL.
class Api::V1::Accounts::Captain::LlmModelsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action -> { authorize(Captain::Assistant, :tools?) }

  def index
    @models = Chatwit::LlmProxy.catalog_models
    @source = @models.present? ? 'central' : 'unavailable'
  end
end
