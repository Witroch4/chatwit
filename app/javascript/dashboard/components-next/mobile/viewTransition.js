import { nextTick } from 'vue';

const NAV_SAFETY_TIMEOUT_MS = 300;

/**
 * Progressive enhancement: envolve uma navegação mobile com a
 * View Transitions API (cross-fade nativo) quando suportada
 * (Chrome 111+, Safari 18+). Sem suporte, a navegação roda
 * exatamente como antes — comportamento idêntico ao atual.
 *
 * @param {Function} navigate fn que dispara a navegação; pode retornar
 *   uma promise (ex.: router.push) para aguardar a troca de DOM.
 */
export const withViewTransition = navigate => {
  if (!document.startViewTransition) {
    navigate();
    return;
  }
  document.startViewTransition(async () => {
    await navigate();
    await nextTick();
  });
};

/**
 * Resolve após a próxima navegação concluída do router (ou após um
 * timeout de segurança). Necessário para navegações via histórico
 * (router.back), que não retornam promise.
 *
 * @param {import('vue-router').Router} router
 */
export const afterNextNavigation = router =>
  new Promise(resolve => {
    let timer;
    const stop = router.afterEach(() => {
      clearTimeout(timer);
      stop();
      resolve();
    });
    timer = setTimeout(() => {
      stop();
      resolve();
    }, NAV_SAFETY_TIMEOUT_MS);
  });
