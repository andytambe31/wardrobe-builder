// Runtime secret lookup (SSM SecureString). Values are fetched on first use and
// cached for the life of the Lambda container, so a warm invocation never pays
// for the round trip. `fetchParam` is injected (SSM in prod, a stub in tests).
export function createSecrets({ fetchParam, ttlMs = 5 * 60 * 1000, now = () => Date.now() }) {
  const cache = new Map(); // name -> { value, at }
  return {
    async get(name) {
      if (!name) throw new Error('secret name not configured');
      const hit = cache.get(name);
      if (hit && now() - hit.at < ttlMs) return hit.value;
      const value = await fetchParam(name);
      if (!value || value === 'REPLACE_ME') throw new Error(`secret ${name} is not set`);
      cache.set(name, { value, at: now() });
      return value;
    },
  };
}
