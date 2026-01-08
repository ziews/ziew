//! JS Bridge - The JavaScript shim injected into every webview page

/// The ziew.js JavaScript code that gets injected
pub const ziew_js: [:0]const u8 =
    \\// Ziew JS Bridge v0.2.0
    \\(function() {
    \\  'use strict';
    \\
    \\  // Pending promise callbacks
    \\  const pending = new Map();
    \\  let nextId = 1;
    \\
    \\  // Streaming callbacks
    \\  const streams = new Map();
    \\
    \\  // Create the ziew namespace
    \\  window.ziew = {
    \\    platform: navigator.platform.includes('Linux') ? 'linux' : navigator.platform.includes('Mac') ? 'macos' : navigator.platform.includes('Win') ? 'windows' : 'unknown',
    \\    version: '0.2.0',
    \\
    \\    // Internal: resolve a pending call
    \\    _resolve: function(id, result) {
    \\      const p = pending.get(id);
    \\      if (p) {
    \\        pending.delete(id);
    \\        p.resolve(result);
    \\      }
    \\    },
    \\
    \\    // Internal: reject a pending call
    \\    _reject: function(id, error) {
    \\      const p = pending.get(id);
    \\      if (p) {
    \\        pending.delete(id);
    \\        p.reject(new Error(error));
    \\      }
    \\    },
    \\
    \\    // Internal: push to a stream
    \\    _streamPush: function(id, chunk) {
    \\      const s = streams.get(id);
    \\      if (s) {
    \\        s.queue.push(chunk);
    \\        if (s.resolver) {
    \\          s.resolver();
    \\          s.resolver = null;
    \\        }
    \\      }
    \\    },
    \\
    \\    // Internal: end a stream
    \\    _streamEnd: function(id) {
    \\      const s = streams.get(id);
    \\      if (s) {
    \\        s.done = true;
    \\        if (s.resolver) {
    \\          s.resolver();
    \\          s.resolver = null;
    \\        }
    \\      }
    \\    },
    \\
    \\    // Namespaces for native APIs
    \\    fs: {},
    \\    shell: {},
    \\    dialog: {},
    \\
    \\    // AI namespace - local LLM inference
    \\    ai: {
    \\      // Generate text completion (returns full response)
    \\      // Options: { maxTokens: 256, temperature: 0.7 }
    \\      complete: function(prompt, options = {}) {
    \\        return new Promise((resolve, reject) => {
    \\          const id = String(nextId++);
    \\          pending.set(id, { resolve, reject });
    \\          if (window.__ziew_ai_complete) {
    \\            window.__ziew_ai_complete(JSON.stringify({ id, prompt, ...options }));
    \\          } else {
    \\            pending.delete(id);
    \\            reject(new Error('AI not available - build with -Dai=true'));
    \\          }
    \\        });
    \\      },
    \\
    \\      // Stream text generation (async generator)
    \\      // Usage: for await (const token of ziew.ai.stream('Hello')) { ... }
    \\      stream: async function*(prompt, options = {}) {
    \\        if (!window.__ziew_ai_stream) {
    \\          throw new Error('AI not available - build with -Dai=true');
    \\        }
    \\
    \\        const id = String(nextId++);
    \\        const stream = {
    \\          queue: [],
    \\          done: false,
    \\          error: null,
    \\          resolver: null
    \\        };
    \\        streams.set(id, stream);
    \\
    \\        window.__ziew_ai_stream(JSON.stringify({ id, prompt, ...options }));
    \\
    \\        try {
    \\          while (!stream.done || stream.queue.length > 0) {
    \\            if (stream.error) {
    \\              throw new Error(stream.error);
    \\            }
    \\            if (stream.queue.length > 0) {
    \\              yield stream.queue.shift();
    \\            } else if (!stream.done) {
    \\              await new Promise(r => stream.resolver = r);
    \\            }
    \\          }
    \\        } finally {
    \\          streams.delete(id);
    \\        }
    \\      },
    \\
    \\      // Check if AI is available
    \\      available: function() {
    \\        return !!window.__ziew_ai_complete;
    \\      }
    \\    },
    \\
    \\    // Lua namespace - backend scripting
    \\    lua: {
    \\      // Call a Lua function by name with arguments
    \\      // Returns a promise that resolves with the result
    \\      call: function(funcName, ...args) {
    \\        return new Promise((resolve, reject) => {
    \\          const id = String(nextId++);
    \\          pending.set(id, { resolve, reject });
    \\          if (window.__ziew_lua_call) {
    \\            window.__ziew_lua_call(JSON.stringify({ id, func: funcName, args }));
    \\          } else {
    \\            pending.delete(id);
    \\            reject(new Error('Lua not available - build with -Dlua=true'));
    \\          }
    \\        });
    \\      },
    \\
    \\      // Check if Lua is available
    \\      available: function() {
    \\        return !!window.__ziew_lua_call;
    \\      }
    \\    },
    \\  };
    \\
    \\  // Helper to create async function wrappers
    \\  window.ziew._wrapAsync = function(nativeFn) {
    \\    return function(...args) {
    \\      return new Promise((resolve, reject) => {
    \\        const id = String(nextId++);
    \\        pending.set(id, { resolve, reject });
    \\        nativeFn(JSON.stringify({ id, args }));
    \\      });
    \\    };
    \\  };
    \\
    \\  // Helper to create streaming function wrappers
    \\  window.ziew._wrapStream = function(nativeFn) {
    \\    return async function*(...args) {
    \\      const id = String(nextId++);
    \\      const stream = {
    \\        queue: [],
    \\        done: false,
    \\        resolver: null
    \\      };
    \\      streams.set(id, stream);
    \\
    \\      nativeFn(JSON.stringify({ id, args, stream: true }));
    \\
    \\      try {
    \\        while (!stream.done || stream.queue.length > 0) {
    \\          if (stream.queue.length > 0) {
    \\            yield stream.queue.shift();
    \\          } else if (!stream.done) {
    \\            await new Promise(r => stream.resolver = r);
    \\          }
    \\        }
    \\      } finally {
    \\        streams.delete(id);
    \\      }
    \\    };
    \\  };
    \\
    \\  console.log('[ziew] Bridge initialized v0.2.0');
    \\})();
;
