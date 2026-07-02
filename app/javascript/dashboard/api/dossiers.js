/* global axios */
import ApiClient from './ApiClient';

// Chatwit: dossier export of selected conversation messages
class DossiersAPI extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  create(conversationId, messageIds) {
    return axios.post(`${this.url}/${conversationId}/dossiers`, {
      message_ids: messageIds,
    });
  }

  status(conversationId, dossierId) {
    return axios.get(`${this.url}/${conversationId}/dossiers/${dossierId}`);
  }
}

export default new DossiersAPI();
