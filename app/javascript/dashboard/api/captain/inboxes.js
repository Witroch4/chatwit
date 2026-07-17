/* global axios */
import ApiClient from '../ApiClient';

class CaptainInboxes extends ApiClient {
  constructor() {
    super('captain/assistants', { accountScoped: true });
  }

  get({ assistantId } = {}) {
    return axios.get(`${this.url}/${assistantId}/inboxes`);
  }

  create(params = {}) {
    const {
      assistantId,
      inboxId,
      mode,
      phase2Model,
      phase2Prompt,
      phase2PaymentPresetIds,
    } = params;
    const inbox = { inbox_id: inboxId };
    if (mode) {
      inbox.mode = mode;
    }
    if (mode === 'phase2_only') {
      inbox.phase2_model = phase2Model || null;
      inbox.phase2_prompt = phase2Prompt || null;
      inbox.phase2_payment_preset_ids = phase2PaymentPresetIds || [];
    }
    return axios.post(`${this.url}/${assistantId}/inboxes`, { inbox });
  }

  delete(params = {}) {
    const { assistantId, inboxId } = params;
    return axios.delete(`${this.url}/${assistantId}/inboxes/${inboxId}`);
  }
}

export default new CaptainInboxes();
