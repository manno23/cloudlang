// examples/kv-store.ts
//
// A key-value store with a cache layer.
// Written as a normal TypeScript program — no Cloudflare awareness.
//
// CloudLang decomposes this into 3 Workers:
//   1. "storage"        — put/get functions, KV binding for store
//   2. "cache"          — cachedGet function, KV + service binding
//   3. "handleRequest"  — routing layer, service bindings to cache + storage

const store = new Map<string, string>();

const put = (key: string, value: string): void => {
  store.set(key, value);
};

const get = (key: string): string | undefined => {
  return store.get(key);
};

const cache = new Map<string, string>();

const cachedGet = (key: string): string | undefined => {
  const hit = cache.get(key);
  if (hit) return hit;
  const result = get(key);
  if (result) {
    cache.set(key, result);
    return result;
  }
  return undefined;
};

const handleRequest = (method: string, key: string, value?: string): string => {
  if (method === "GET") {
    return cachedGet(key) ?? "NOT_FOUND";
  }
  if (method === "PUT" && value) {
    put(key, value);
    return "OK";
  }
  return "BAD_REQUEST";
};

export { handleRequest };
