/* eslint-disable no-restricted-globals, no-console */
/* globals clients */

/**
 * PWA service worker for Chatwit.
 *
 * Mirrors the helpers from app/javascript/shared/helpers/pwaPushNotification.js
 * (the canonical, tested copy) so that the worker stays a single classic
 * script and remains compatible with iOS 16.4+ Web Push. Keep both copies in
 * sync when editing.
 */

const RECENT_PUSH_TTL = 10000;
const DEFAULT_VIBRATE_PATTERN = [300, 150, 300, 150, 450];
const DEFAULT_ICON = '/android-icon-192x192.png';
const DEFAULT_BADGE = '/favicon-96x96.png';
const REPLY_PLACEHOLDER_FALLBACK = 'Reply...';
const REPLY_FAILURE_TAG = 'pwa-reply-failure';

const NOTIFICATION_ACTIONS = {
  REPLY: 'reply',
  MARK_READ: 'mark_read',
  OPEN: 'open',
};

const recentPushes = new Map();

const PWA_AUTH_DB_NAME = 'chatwit-pwa-auth';
const PWA_AUTH_STORE = 'sessions';
const PWA_AUTH_KEY = 'current';

const trimText = value => (typeof value === 'string' ? value.trim() : '');

const buildNotificationKey = payload => {
  if (!payload) return '';
  return [payload.tag, payload.title, payload.body, payload.url]
    .filter(Boolean)
    .join('::');
};

const isRecentDuplicate = key => {
  if (!key) return false;
  const ts = recentPushes.get(key);
  if (!ts) return false;
  return Date.now() - ts < RECENT_PUSH_TTL;
};

const rememberNotification = key => {
  if (!key) return;
  const now = Date.now();
  recentPushes.set(key, now);
  recentPushes.forEach((ts, storedKey) => {
    if (now - ts >= RECENT_PUSH_TTL) recentPushes.delete(storedKey);
  });
};

const sanitizeReplyText = text => {
  if (typeof text !== 'string') return '';
  return text.replace(/\r/g, '').trim().slice(0, 4000);
};

const buildReplyPlaceholder = (payload, fallback = 'Reply') => {
  const senderName = trimText(payload && payload.sender && payload.sender.name);
  if (!senderName) return `${fallback}…`;
  return `${fallback} ${senderName}…`;
};

const isReplyAllowed = payload => Boolean(payload && payload.reply_enabled);

const isMarkReadAllowed = payload =>
  Boolean(payload && payload.account_id && payload.notification_id);

const buildNotificationActions = (payload, labels) => {
  const actions = [];
  if (isReplyAllowed(payload)) {
    actions.push({
      action: NOTIFICATION_ACTIONS.REPLY,
      title: labels.reply || 'Reply',
      type: 'text',
      placeholder: buildReplyPlaceholder(payload, labels.replyPlaceholder),
      icon: '/favicon-96x96.png',
    });
  }
  if (isMarkReadAllowed(payload)) {
    actions.push({
      action: NOTIFICATION_ACTIONS.MARK_READ,
      title: labels.markRead || 'Mark as read',
      icon: '/favicon-96x96.png',
    });
  }
  return actions;
};

const buildNotificationOptions = (payload, labels) => {
  const senderAvatar = trimText(
    payload && payload.sender && payload.sender.avatar_url
  );
  const icon = senderAvatar || DEFAULT_ICON;
  return {
    body: (payload && payload.body) || '',
    tag: payload && payload.tag,
    icon,
    badge: DEFAULT_BADGE,
    image: senderAvatar || undefined,
    timestamp: (payload && payload.timestamp) || Date.now(),
    renotify: false,
    requireInteraction: false,
    silent: false,
    vibrate:
      Array.isArray(payload && payload.vibrate) && payload.vibrate.length
        ? payload.vibrate
        : DEFAULT_VIBRATE_PATTERN,
    actions: buildNotificationActions(payload, labels),
    data: {
      url: payload && payload.url,
      account_id: payload && payload.account_id,
      conversation_id: payload && payload.conversation_id,
      conversation_uuid: payload && payload.conversation_uuid,
      notification_id: payload && payload.notification_id,
      notification_type: payload && payload.notification_type,
      reply_enabled: isReplyAllowed(payload),
      sender: (payload && payload.sender) || null,
      replyPlaceholder:
        (labels && labels.replyPlaceholder) || REPLY_PLACEHOLDER_FALLBACK,
    },
  };
};

const buildOpenWindowUrl = (data, action) => {
  if (!data || !data.url) return null;
  let target;
  try {
    target = new URL(data.url, self.location.origin);
  } catch (e) {
    return null;
  }
  if (action === NOTIFICATION_ACTIONS.REPLY) {
    target.searchParams.set('focus_reply', '1');
  }
  return target.toString();
};

const buildReplyApiUrl = data => {
  if (!data || !data.account_id || !data.conversation_id) return null;
  return `${self.location.origin}/api/v1/accounts/${data.account_id}/conversations/${data.conversation_id}/messages`;
};

const buildMarkReadApiUrl = data => {
  if (!data || !data.account_id || !data.notification_id) return null;
  return `${self.location.origin}/api/v1/accounts/${data.account_id}/notifications/${data.notification_id}`;
};

const buildAuthHeaders = credentials => {
  if (!credentials) return null;
  if (!credentials.accessToken || !credentials.client || !credentials.uid) {
    return null;
  }
  return {
    'Content-Type': 'application/json',
    'access-token': credentials.accessToken,
    'token-type': credentials.tokenType || 'Bearer',
    client: credentials.client,
    expiry: credentials.expiry || '',
    uid: credentials.uid,
  };
};

const buildReplyRequestBody = (replyText, data) => {
  const sanitized = sanitizeReplyText(replyText);
  if (!sanitized) return null;
  return JSON.stringify({
    content: sanitized,
    private: false,
    echo_id: `pwa-reply-${(data && data.notification_id) || ''}-${Date.now()}`,
  });
};

const openAuthDb = () =>
  new Promise((resolve, reject) => {
    if (typeof indexedDB === 'undefined') {
      reject(new Error('IndexedDB unavailable'));
      return;
    }
    const request = indexedDB.open(PWA_AUTH_DB_NAME, 1);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(PWA_AUTH_STORE)) {
        db.createObjectStore(PWA_AUTH_STORE);
      }
    };
    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve(request.result);
  });

const readStoredSession = async () => {
  try {
    const db = await openAuthDb();
    return await new Promise((resolve, reject) => {
      const tx = db.transaction(PWA_AUTH_STORE, 'readonly');
      const store = tx.objectStore(PWA_AUTH_STORE);
      const req = store.get(PWA_AUTH_KEY);
      req.onsuccess = () => {
        db.close();
        resolve(req.result || null);
      };
      req.onerror = () => {
        db.close();
        reject(req.error);
      };
    });
  } catch (err) {
    console.warn('SW: failed to read stored session', err);
    return null;
  }
};

const showFailureNotification = async (message, data = null) => {
  try {
    await self.registration.showNotification('Could not send reply', {
      body: message,
      icon: DEFAULT_ICON,
      badge: DEFAULT_BADGE,
      tag: REPLY_FAILURE_TAG,
      renotify: true,
      data,
    });
  } catch (err) {
    console.warn('SW: failed to show failure notification', err);
  }
};

const focusOrOpenWindow = async targetUrl => {
  if (!targetUrl) return null;
  const windowClients = await clients.matchAll({
    type: 'window',
    includeUncontrolled: true,
  });
  let parsed;
  try {
    parsed = new URL(targetUrl, self.location.origin);
  } catch (e) {
    return clients.openWindow ? clients.openWindow(targetUrl) : null;
  }

  const samePath = windowClients.find(client => {
    try {
      const clientUrl = new URL(client.url);
      return clientUrl.pathname === parsed.pathname;
    } catch (e) {
      return false;
    }
  });
  if (samePath && 'focus' in samePath) {
    if ('navigate' in samePath && samePath.url !== parsed.toString()) {
      try {
        await samePath.navigate(parsed.toString());
      } catch (err) {
        // Navigation can fail across origins / cross-document; ignore.
      }
    }
    return samePath.focus();
  }

  if (windowClients.length > 0) {
    const fallback = windowClients[0];
    if ('focus' in fallback) {
      await fallback.focus();
      if ('navigate' in fallback) {
        try {
          return await fallback.navigate(parsed.toString());
        } catch (err) {
          // Fall through to openWindow.
        }
      }
    }
  }

  return clients.openWindow ? clients.openWindow(parsed.toString()) : null;
};

const broadcastToClients = async message => {
  try {
    const windowClients = await clients.matchAll({
      type: 'window',
      includeUncontrolled: true,
    });
    windowClients.forEach(client => {
      try {
        client.postMessage(message);
      } catch (err) {
        // Ignore individual postMessage failures.
      }
    });
  } catch (err) {
    console.warn('SW: broadcast failed', err);
  }
};

const performReply = async (data, replyText) => {
  const body = buildReplyRequestBody(replyText, data);
  if (!body) return { ok: false, reason: 'empty' };

  const session = await readStoredSession();
  const credentials = session && session.credentials;
  const headers = buildAuthHeaders(credentials);
  const url = buildReplyApiUrl(data);
  if (!headers || !url) return { ok: false, reason: 'no-auth' };

  try {
    const response = await fetch(url, {
      method: 'POST',
      headers,
      body,
      credentials: 'include',
    });
    if (!response.ok) {
      return { ok: false, reason: `http-${response.status}` };
    }
    return { ok: true };
  } catch (err) {
    return { ok: false, reason: 'network' };
  }
};

const performMarkRead = async data => {
  const session = await readStoredSession();
  const credentials = session && session.credentials;
  const headers = buildAuthHeaders(credentials);
  const url = buildMarkReadApiUrl(data);
  if (!headers || !url) return { ok: false, reason: 'no-auth' };

  try {
    const response = await fetch(url, {
      method: 'PATCH',
      headers,
      credentials: 'include',
      body: '{}',
    });
    return { ok: response.ok };
  } catch (err) {
    return { ok: false, reason: 'network' };
  }
};

// App icon badge while the app is closed: the open app mirrors the store's
// unread count (useAppBadge.js); here the best-effort proxy is the number of
// notifications still on screen. iOS 16.4+ (installed PWA) and Android.
const updateAppBadge = async () => {
  if (!self.navigator || !('setAppBadge' in self.navigator)) return;
  try {
    const notifications = await self.registration.getNotifications();
    const count = notifications.filter(
      notif => notif.tag !== REPLY_FAILURE_TAG
    ).length;
    if (count > 0) await self.navigator.setAppBadge(count);
    else await self.navigator.clearAppBadge();
  } catch (err) {
    // badge is best-effort only
  }
};

// Offline shell: navigations prefer the network but fall back to the cached
// shell once it is slower than NAVIGATION_NETWORK_TIMEOUT_MS, hashed build
// assets are stale-while-revalidate. API/websocket traffic is never touched.
const SHELL_CACHE = 'chatwit-shell-v1';
const SHELL_PRECACHE_URLS = [
  '/',
  '/manifest.json',
  '/android-icon-192x192.png',
  '/favicon-96x96.png',
];
const BUILD_ASSET_RE = /\/(vite|vite-dev|packs|assets)\//;

// Cold starts on a phone routinely hit a radio that is still waking up: the
// navigation fetch then hangs for up to a minute before it rejects, and the
// PWA sits on a frozen blank screen the whole time (killing and reopening the
// app is what "fixes" it). Race the network against a short timer and fall
// back to the cached shell, revalidating in the background.
const NAVIGATION_NETWORK_TIMEOUT_MS = 2000;

self.addEventListener('install', event => {
  event.waitUntil(
    caches
      .open(SHELL_CACHE)
      .then(cache => cache.addAll(SHELL_PRECACHE_URLS))
      .catch(() => {})
  );
  self.skipWaiting();
});

self.addEventListener('activate', event => {
  event.waitUntil(
    (async () => {
      // Lets the browser start the navigation request in parallel with booting
      // this worker, instead of paying the worker startup cost first.
      if (self.registration.navigationPreload) {
        await self.registration.navigationPreload.enable().catch(() => {});
      }
      const keys = await caches.keys();
      await Promise.all(
        keys
          .filter(
            key => key.startsWith('chatwit-shell-') && key !== SHELL_CACHE
          )
          .map(key => caches.delete(key))
      );
      await self.clients.claim();
    })()
  );
});

self.addEventListener('fetch', event => {
  const { request } = event;
  if (request.method !== 'GET') return;

  let url;
  try {
    url = new URL(request.url);
  } catch (e) {
    return;
  }
  if (url.origin !== self.location.origin) return;
  if (url.pathname.startsWith('/api/') || url.pathname.startsWith('/cable')) {
    return;
  }

  if (request.mode === 'navigate') {
    event.respondWith(
      (async () => {
        const cache = await caches.open(SHELL_CACHE);
        const fromNetwork = (async () => {
          const preloaded = await event.preloadResponse;
          const response = preloaded || (await fetch(request));
          // cache.put rejects on redirected responses; the shell is only a
          // fallback, so a miss is not worth failing the navigation over.
          if (response.ok) cache.put(request, response.clone()).catch(() => {});
          return response;
        })();

        const cached =
          (await cache.match(request, { ignoreSearch: true })) ||
          (await cache.match('/', { ignoreSearch: true }));
        // First ever load: there is nothing to show yet, so wait for the network.
        if (!cached) return fromNetwork;

        let timer;
        const winner = await Promise.race([
          fromNetwork.catch(() => null),
          new Promise(resolve => {
            timer = setTimeout(
              () => resolve(null),
              NAVIGATION_NETWORK_TIMEOUT_MS
            );
          }),
        ]);
        clearTimeout(timer);
        if (winner) return winner;

        // Slow or dead network: paint the cached shell now and let the fresh
        // one land in the cache for the next launch. The hashed assets that
        // shell references live in this same cache, so the app stays coherent.
        event.waitUntil(fromNetwork.catch(() => {}));
        return cached;
      })()
    );
    return;
  }

  if (BUILD_ASSET_RE.test(url.pathname)) {
    event.respondWith(
      (async () => {
        const cache = await caches.open(SHELL_CACHE);
        const cached = await cache.match(request);
        const network = fetch(request)
          .then(response => {
            if (response.ok) cache.put(request, response.clone());
            return response;
          })
          .catch(() => null);
        return cached || (await network) || Response.error();
      })()
    );
  }
});

self.addEventListener('message', event => {
  // Page already wrote the session to IDB on PWA_AUTH_UPDATED; the message
  // simply keeps the worker awake long enough for the write to flush. Other
  // message types are ignored.
  if (event.data && event.data.type === 'PWA_AUTH_UPDATED') {
    self.lastAuthUpdate = Date.now();
  }
});

self.addEventListener('push', event => {
  const payload = event.data && event.data.json();
  if (!payload) return;

  const labels = (payload && payload.labels) || {
    reply: 'Reply',
    markRead: 'Mark as read',
    replyPlaceholder: 'Reply',
  };
  const options = buildNotificationOptions(payload, labels);
  const notificationKey = buildNotificationKey(payload);

  event.waitUntil(
    (async () => {
      if (isRecentDuplicate(notificationKey)) return;

      // When the same conversation pushes again, swap the existing notification
      // (renotify=false on iOS prevents alert spam but we still want the latest
      // body to surface when the user expands).
      if (payload.tag) {
        const existing = await self.registration.getNotifications({
          tag: payload.tag,
        });
        existing.forEach(notif => notif.close());
      }

      rememberNotification(notificationKey);
      await self.registration.showNotification(payload.title, options);
      await updateAppBadge();
    })()
  );
});

const handleReplyAction = async (notification, replyText) => {
  const { data } = notification;
  const trimmed = sanitizeReplyText(replyText);

  // Inline reply text is supported on Chrome/Android. iOS swallows the text
  // and we fall back to opening the PWA focused on the reply box.
  if (!trimmed) {
    const url = buildOpenWindowUrl(data, NOTIFICATION_ACTIONS.REPLY);
    return focusOrOpenWindow(url);
  }

  const result = await performReply(data, trimmed);
  if (result.ok) {
    await broadcastToClients({
      type: 'PWA_REPLY_SENT',
      conversation_id: data.conversation_id,
      account_id: data.account_id,
    });
    return null;
  }

  if (result.reason === 'no-auth') {
    const fallbackUrl = buildOpenWindowUrl(data, NOTIFICATION_ACTIONS.REPLY);
    await focusOrOpenWindow(fallbackUrl);
    return showFailureNotification(
      'Sign in to the app to enable instant reply.',
      data
    );
  }

  await showFailureNotification(
    `We could not deliver your reply (${result.reason}). Open the app to retry.`,
    data
  );
  const fallbackUrl = buildOpenWindowUrl(data, NOTIFICATION_ACTIONS.REPLY);
  return focusOrOpenWindow(fallbackUrl);
};

const handleMarkReadAction = async notification => {
  const { data } = notification;
  const result = await performMarkRead(data);
  if (result.ok) {
    await broadcastToClients({
      type: 'PWA_NOTIFICATION_READ',
      notification_id: data.notification_id,
      conversation_id: data.conversation_id,
    });
  }
};

self.addEventListener('notificationclick', event => {
  const { notification, action, reply } = event;
  notification.close();

  if (action === NOTIFICATION_ACTIONS.REPLY) {
    event.waitUntil(
      handleReplyAction(notification, reply).then(updateAppBadge)
    );
    return;
  }

  if (action === NOTIFICATION_ACTIONS.MARK_READ) {
    event.waitUntil(handleMarkReadAction(notification).then(updateAppBadge));
    return;
  }

  const targetUrl = buildOpenWindowUrl(
    notification.data,
    NOTIFICATION_ACTIONS.OPEN
  );
  event.waitUntil(focusOrOpenWindow(targetUrl).then(updateAppBadge));
});
