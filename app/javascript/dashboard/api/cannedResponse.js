/* global axios */

import ApiClient from './ApiClient';

class CannedResponse extends ApiClient {
  constructor() {
    super('canned_responses', { accountScoped: true });
  }

  get({ searchKey }) {
    const url = searchKey ? `${this.url}?search=${searchKey}` : this.url;
    return axios.get(url);
  }

  reorder(cannedResponseIds) {
    return axios.post(`${this.url}/reorder`, {
      canned_response_ids: cannedResponseIds,
    });
  }
}

export default new CannedResponse();
