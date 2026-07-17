import ApiClient from '../ApiClient';

class CaptainLlmModels extends ApiClient {
  constructor() {
    super('captain/llm_models', { accountScoped: true });
  }
}

export default new CaptainLlmModels();
