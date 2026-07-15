import types from '../../mutation-types';
import { mutations } from '../whatsappInteractiveTemplates';

describe('#whatsappInteractiveTemplates mutations', () => {
  it('replaces an updated template in the store', () => {
    const state = {
      records: [
        { id: 1, name: 'Original CTA', body_text: 'Original body' },
        { id: 2, name: 'Other CTA', body_text: 'Other body' },
      ],
    };
    const updatedTemplate = {
      id: 1,
      name: 'Updated CTA',
      body_text: 'Updated body',
    };

    mutations[types.EDIT_WHATSAPP_INTERACTIVE_TEMPLATE](state, updatedTemplate);

    expect(state.records).toEqual([updatedTemplate, state.records[1]]);
  });
});
