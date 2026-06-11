import { onBeforeUnmount, onMounted } from 'vue';
import { useStore } from 'dashboard/composables/store';

// Fila offline de envio (texto apenas): mensagens escritas sem rede ficam em
// localStorage e saem pelo MESMO dispatch usado no envio normal
// (`createPendingMessageAndSend`) assim que a conexão volta. Falhas de envio
// pós-flush seguem o fluxo padrão (bolha "failed" com retry), como online.
const STORAGE_KEY = 'chatwit_mobile_outbox';

const readQueue = () => {
  try {
    return JSON.parse(window.localStorage.getItem(STORAGE_KEY)) || [];
  } catch {
    return [];
  }
};

const writeQueue = queue => {
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(queue));
  } catch {
    // storage indisponível: fila é best-effort
  }
};

export const enqueueOutboxMessage = payload => {
  writeQueue([...readQueue(), payload]);
};

export const outboxCount = () => readQueue().length;

// Montar uma única vez no shell mobile (MobileLayout): escuta `online` e
// drena a fila na ordem em que as mensagens foram escritas.
export const useOfflineOutbox = ({ onFlushed } = {}) => {
  const store = useStore();

  const flush = () => {
    if (typeof navigator !== 'undefined' && !navigator.onLine) return;
    const queue = readQueue();
    if (!queue.length) return;
    writeQueue([]);
    queue.forEach(payload => {
      store.dispatch('createPendingMessageAndSend', payload);
    });
    onFlushed?.(queue.length);
  };

  onMounted(() => {
    window.addEventListener('online', flush);
    flush();
  });

  onBeforeUnmount(() => {
    window.removeEventListener('online', flush);
  });

  return { flush };
};

export default useOfflineOutbox;
