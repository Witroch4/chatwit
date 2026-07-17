<script setup>
import { reactive, computed, ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { useMapGetter } from 'dashboard/composables/store';

import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

import CaptainLlmModels from 'dashboard/api/captain/llmModels';
import PaymentPresetsAPI from 'dashboard/api/paymentPresets';

const props = defineProps({
  assistantId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['submit', 'cancel']);

const { t } = useI18n();

const formState = {
  uiFlags: useMapGetter('captainInboxes/getUIFlags'),
  inboxes: useMapGetter('inboxes/getInboxes'),
  captainInboxes: useMapGetter('captainInboxes/getRecords'),
};

const initialState = {
  inboxId: null,
  mode: 'continuous',
  phase2Model: '',
  phase2Prompt: '',
  phase2PixKey: '',
  phase2PaymentPresetIds: [],
};

const state = reactive({ ...initialState });

const llmModels = ref([]);
const paymentPresets = ref([]);

const validationRules = {
  inboxId: { required },
};

const inboxList = computed(() => {
  const captainInboxIds = formState.captainInboxes.value.map(inbox => inbox.id);

  return formState.inboxes.value
    .filter(inbox => !captainInboxIds.includes(inbox.id))
    .map(inbox => ({
      value: inbox.id,
      label: inbox.name,
    }));
});

const modeOptions = computed(() => [
  { value: 'continuous', label: t('CAPTAIN.INBOXES.FORM.MODE.CONTINUOUS') },
  { value: 'phase2_only', label: t('CAPTAIN.INBOXES.FORM.MODE.PHASE2_ONLY') },
]);

const modelOptions = computed(() => [
  { value: '', label: t('CAPTAIN.INBOXES.FORM.PHASE2_MODEL.DEFAULT') },
  ...llmModels.value.map(model => ({
    value: model.value,
    label: model.provider_label
      ? `${model.label} (${model.provider_label})`
      : model.label,
  })),
]);

const isPhase2 = computed(() => state.mode === 'phase2_only');

const v$ = useVuelidate(validationRules, state);

const isLoading = computed(() => formState.uiFlags.value.creatingItem);

const getErrorMessage = (field, errorKey) => {
  return v$.value[field].$error
    ? t(`CAPTAIN.INBOXES.FORM.${errorKey}.ERROR`)
    : '';
};

const formErrors = computed(() => ({
  inboxId: getErrorMessage('inboxId', 'INBOX'),
}));

const togglePreset = presetId => {
  const index = state.phase2PaymentPresetIds.indexOf(presetId);
  if (index === -1) {
    state.phase2PaymentPresetIds.push(presetId);
  } else {
    state.phase2PaymentPresetIds.splice(index, 1);
  }
};

const loadPhase2Options = async () => {
  try {
    const [modelsResponse, presetsResponse] = await Promise.all([
      CaptainLlmModels.get(),
      PaymentPresetsAPI.get(),
    ]);
    llmModels.value = modelsResponse.data?.models || [];
    paymentPresets.value =
      presetsResponse.data?.payload || presetsResponse.data || [];
  } catch (error) {
    llmModels.value = [];
    paymentPresets.value = [];
  }
};

onMounted(loadPhase2Options);

const handleCancel = () => emit('cancel');

const prepareInboxPayload = () => ({
  inboxId: state.inboxId,
  assistantId: props.assistantId,
  mode: state.mode,
  phase2Model: isPhase2.value ? state.phase2Model : null,
  phase2Prompt: isPhase2.value ? state.phase2Prompt : null,
  phase2PixKey: isPhase2.value ? state.phase2PixKey : null,
  phase2PaymentPresetIds: isPhase2.value ? state.phase2PaymentPresetIds : [],
});

const handleSubmit = async () => {
  const isFormValid = await v$.value.$validate();
  if (!isFormValid) {
    return;
  }

  emit('submit', prepareInboxPayload());
};
</script>

<template>
  <form class="flex flex-col gap-4" @submit.prevent="handleSubmit">
    <div class="flex flex-col gap-1">
      <label for="inbox" class="mb-0.5 text-sm font-medium text-n-slate-12">
        {{ t('CAPTAIN.INBOXES.FORM.INBOX.LABEL') }}
      </label>
      <ComboBox
        id="inbox"
        v-model="state.inboxId"
        :options="inboxList"
        :has-error="!!formErrors.inboxId"
        :placeholder="t('CAPTAIN.INBOXES.FORM.INBOX.PLACEHOLDER')"
        class="[&>div>button]:bg-n-alpha-black2 [&>div>button:not(.focused)]:dark:outline-n-weak [&>div>button:not(.focused)]:hover:!outline-n-slate-6"
        :message="formErrors.inboxId"
      />
    </div>

    <div class="flex flex-col gap-1">
      <label for="mode" class="mb-0.5 text-sm font-medium text-n-slate-12">
        {{ t('CAPTAIN.INBOXES.FORM.MODE.LABEL') }}
      </label>
      <ComboBox
        id="mode"
        v-model="state.mode"
        :options="modeOptions"
        class="[&>div>button]:bg-n-alpha-black2 [&>div>button:not(.focused)]:dark:outline-n-weak [&>div>button:not(.focused)]:hover:!outline-n-slate-6"
      />
    </div>

    <template v-if="isPhase2">
      <div class="flex flex-col gap-1">
        <label
          for="phase2-model"
          class="mb-0.5 text-sm font-medium text-n-slate-12"
        >
          {{ t('CAPTAIN.INBOXES.FORM.PHASE2_MODEL.LABEL') }}
        </label>
        <ComboBox
          id="phase2-model"
          v-model="state.phase2Model"
          :options="modelOptions"
          class="[&>div>button]:bg-n-alpha-black2 [&>div>button:not(.focused)]:dark:outline-n-weak [&>div>button:not(.focused)]:hover:!outline-n-slate-6"
        />
      </div>

      <div class="flex flex-col gap-1">
        <label
          for="phase2-prompt"
          class="mb-0.5 text-sm font-medium text-n-slate-12"
        >
          {{ t('CAPTAIN.INBOXES.FORM.PHASE2_PROMPT.LABEL') }}
        </label>
        <textarea
          id="phase2-prompt"
          v-model="state.phase2Prompt"
          rows="5"
          :placeholder="t('CAPTAIN.INBOXES.FORM.PHASE2_PROMPT.PLACEHOLDER')"
          class="w-full p-3 text-sm border rounded-lg bg-n-alpha-black2 border-n-weak text-n-slate-12"
        />
      </div>

      <div class="flex flex-col gap-1">
        <label
          for="phase2-pix-key"
          class="mb-0.5 text-sm font-medium text-n-slate-12"
        >
          {{ t('CAPTAIN.INBOXES.FORM.PHASE2_PIX_KEY.LABEL') }}
        </label>
        <input
          id="phase2-pix-key"
          v-model="state.phase2PixKey"
          type="text"
          :placeholder="t('CAPTAIN.INBOXES.FORM.PHASE2_PIX_KEY.PLACEHOLDER')"
          class="w-full p-3 text-sm border rounded-lg bg-n-alpha-black2 border-n-weak text-n-slate-12"
        />
        <p class="text-xs text-n-slate-11">
          {{ t('CAPTAIN.INBOXES.FORM.PHASE2_PIX_KEY.HELP') }}
        </p>
      </div>

      <div class="flex flex-col gap-1">
        <span class="mb-0.5 text-sm font-medium text-n-slate-12">
          {{ t('CAPTAIN.INBOXES.FORM.PHASE2_PRESETS.LABEL') }}
        </span>
        <p v-if="!paymentPresets.length" class="text-sm text-n-slate-11">
          {{ t('CAPTAIN.INBOXES.FORM.PHASE2_PRESETS.EMPTY') }}
        </p>
        <label
          v-for="preset in paymentPresets"
          :key="preset.id"
          class="flex items-center gap-2 text-sm text-n-slate-12"
        >
          <input
            type="checkbox"
            :value="preset.id"
            :checked="state.phase2PaymentPresetIds.includes(preset.id)"
            @change="togglePreset(preset.id)"
          />
          {{ preset.name }}
        </label>
      </div>
    </template>

    <div class="flex items-center justify-between w-full gap-3">
      <Button
        type="button"
        variant="faded"
        color="slate"
        :label="t('CAPTAIN.FORM.CANCEL')"
        class="w-full bg-n-alpha-2 text-n-blue-11 hover:bg-n-alpha-3"
        @click="handleCancel"
      />
      <Button
        type="submit"
        :label="t('CAPTAIN.FORM.CREATE')"
        class="w-full"
        :is-loading="isLoading"
        :disabled="isLoading"
      />
    </div>
  </form>
</template>
