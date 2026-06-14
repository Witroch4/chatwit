<script setup>
import { computed } from 'vue';
import { useMessageContext } from '../provider.js';

const { attachments } = useMessageContext();

const url = computed(
  () => attachments.value[0]?.dataUrl || attachments.value[0]?.thumbUrl
);
</script>

<template>
  <img
    v-if="url"
    :src="url"
    alt=""
    class="object-contain w-32 h-32 max-w-full bg-transparent rounded-lg"
  />
</template>
