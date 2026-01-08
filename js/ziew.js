// Ziew JS Bridge v0.2.0
// This file is embedded into the Zig binary and injected into every webview page.

(function() {
  'use strict';

  // Pending promise callbacks
  const pending = new Map();
  let nextId = 1;

  // Streaming callbacks
  const streams = new Map();

  // Create the ziew namespace
  window.ziew = {
    platform: navigator.platform.includes('Linux') ? 'linux' : navigator.platform.includes('Mac') ? 'macos' : navigator.platform.includes('Win') ? 'windows' : 'unknown',
    version: '0.2.0',

    // Internal: resolve a pending call
    _resolve: function(id, result) {
      const p = pending.get(id);
      if (p) {
        pending.delete(id);
        p.resolve(result);
      }
    },

    // Internal: reject a pending call
    _reject: function(id, error) {
      const p = pending.get(id);
      if (p) {
        pending.delete(id);
        p.reject(new Error(error));
      }
    },

    // Internal: push to a stream
    _streamPush: function(id, chunk) {
      const s = streams.get(id);
      if (s) {
        s.queue.push(chunk);
        if (s.resolver) {
          s.resolver();
          s.resolver = null;
        }
      }
    },

    // Internal: end a stream
    _streamEnd: function(id) {
      const s = streams.get(id);
      if (s) {
        s.done = true;
        if (s.resolver) {
          s.resolver();
          s.resolver = null;
        }
      }
    },

    // Namespaces for native APIs
    fs: {},
    ai: {},
    shell: {},
    dialog: {},
    lua: {},
  };

  // Helper to create async function wrappers
  window.ziew._wrapAsync = function(nativeFn) {
    return function(...args) {
      return new Promise((resolve, reject) => {
        const id = String(nextId++);
        pending.set(id, { resolve, reject });
        nativeFn(JSON.stringify({ id, args }));
      });
    };
  };

  // Helper to create streaming function wrappers
  window.ziew._wrapStream = function(nativeFn) {
    return async function*(...args) {
      const id = String(nextId++);
      const stream = {
        queue: [],
        done: false,
        resolver: null
      };
      streams.set(id, stream);

      nativeFn(JSON.stringify({ id, args, stream: true }));

      try {
        while (!stream.done || stream.queue.length > 0) {
          if (stream.queue.length > 0) {
            yield stream.queue.shift();
          } else if (!stream.done) {
            await new Promise(r => stream.resolver = r);
          }
        }
      } finally {
        streams.delete(id);
      }
    };
  };

  console.log('[ziew] Bridge initialized v0.2.0');
})();
