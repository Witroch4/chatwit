/* global axios */
import ApiClient from './ApiClient';

class StickersAPI extends ApiClient {
  constructor() {
    super('stickers', { accountScoped: true });
  }

  getRecent() {
    return axios.get(this.url, { params: { recent: true } });
  }

  create(formData) {
    return axios.post(this.url, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  createFromAttachment(sourceAttachmentId) {
    return axios.post(this.url, { source_attachment_id: sourceAttachmentId });
  }

  send({ stickerId, conversationId }) {
    return axios.post(`${this.url}/${stickerId}/send_sticker`, {
      conversation_id: conversationId,
    });
  }
}

export default new StickersAPI();
