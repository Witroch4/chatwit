/* eslint-disable no-console */
import NotificationSubscriptions from '../api/notificationSubscription';
import auth from '../api/auth';
import { useAlert } from 'dashboard/composables';
import { syncSessionToServiceWorker } from './swAuthBridge';

// The worker also backs the offline shell that the PWA cold start depends on,
// so registering it must not hinge on push support: iOS only exposes
// PushManager to installed web apps.
export const registerServiceWorker = () => {
  if (!('serviceWorker' in navigator)) {
    // Service Worker isn't supported on this browser, disable or hide UI.
    return Promise.resolve(null);
  }

  return navigator.serviceWorker.register('/sw.js').catch(registrationError => {
    // eslint-disable-next-line
    console.log('SW registration failed: ', registrationError);
    return null;
  });
};

export const verifyServiceWorkerExistence = (callback = () => {}) => {
  if (!('PushManager' in window)) {
    // Push isn't supported on this browser, disable or hide UI.
    return;
  }

  registerServiceWorker().then(registration => {
    if (registration) callback(registration);
  });
};

export const hasPushPermissions = () => {
  if ('Notification' in window) {
    return Notification.permission === 'granted';
  }
  return false;
};

const generateKeys = str =>
  btoa(String.fromCharCode.apply(null, new Uint8Array(str)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_');

export const getPushSubscriptionPayload = subscription => ({
  subscription_type: 'browser_push',
  subscription_attributes: {
    endpoint: subscription.endpoint,
    p256dh: generateKeys(subscription.getKey('p256dh')),
    auth: generateKeys(subscription.getKey('auth')),
  },
});

export const sendRegistrationToServer = subscription => {
  if (auth.hasAuthCookie()) {
    return NotificationSubscriptions.create(
      getPushSubscriptionPayload(subscription)
    );
  }
  return null;
};

export const syncPwaAuthBridge = ({ accountId, userId } = {}) => {
  if (!auth.hasAuthCookie()) return Promise.resolve(false);
  return syncSessionToServiceWorker({ accountId, userId }).catch(error => {
    console.warn('PWA auth bridge sync failed', error);
    return false;
  });
};

export const removeRegistrationFromServer = subscription => {
  if (auth.hasAuthCookie() && subscription?.endpoint) {
    return NotificationSubscriptions.destroy({
      endpoint: subscription.endpoint,
    });
  }

  return null;
};

export const registerSubscription = (onSuccess = () => {}) => {
  if (!window.chatwootConfig.vapidPublicKey) {
    return;
  }
  navigator.serviceWorker.ready
    .then(serviceWorkerRegistration =>
      serviceWorkerRegistration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: window.chatwootConfig.vapidPublicKey,
      })
    )
    .then(sendRegistrationToServer)
    .then(() => syncPwaAuthBridge())
    .then(() => {
      onSuccess();
    })
    .catch(error => {
      // eslint-disable-next-line no-console
      console.error('Push subscription registration failed:', error);
      useAlert('This browser does not support desktop notification');
    });
};

export const unregisterSubscription = (onSuccess = () => {}) => {
  return navigator.serviceWorker.ready
    .then(serviceWorkerRegistration =>
      serviceWorkerRegistration.pushManager.getSubscription()
    )
    .then(subscription => {
      if (!subscription) {
        return null;
      }

      return Promise.allSettled([
        removeRegistrationFromServer(subscription),
        subscription.unsubscribe(),
      ]).then(([, unsubscribeResult]) => {
        if (unsubscribeResult?.status === 'rejected') {
          throw unsubscribeResult.reason;
        }

        if (unsubscribeResult?.value === false) {
          throw new Error('Push subscription removal failed');
        }

        return subscription;
      });
    })
    .then(() => {
      onSuccess();
    })
    .catch(error => {
      // eslint-disable-next-line no-console
      console.error('Push subscription removal failed:', error);
      throw error;
    });
};

export const requestPushPermissions = ({ onSuccess }) => {
  if (!('Notification' in window)) {
    // eslint-disable-next-line no-console
    console.warn('Notification is not supported');
    useAlert('This browser does not support desktop notification');
  } else if (Notification.permission === 'granted') {
    registerSubscription(onSuccess);
  } else if (Notification.permission !== 'denied') {
    Notification.requestPermission(permission => {
      if (permission === 'granted') {
        registerSubscription(onSuccess);
      }
    });
  }
};
