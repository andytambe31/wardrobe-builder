// A tiny method + path router with :params. No dependencies.
export function createRouter() {
  const routes = [];
  const add = (method, path, handler, opts = {}) => {
    const keys = [];
    const rx = new RegExp('^' + path.replace(/:[^/]+/g, (m) => { keys.push(m.slice(1)); return '([^/]+)'; }) + '/?$');
    routes.push({ method, rx, keys, handler, public: !!opts.public });
  };
  return {
    get: (p, h, o) => add('GET', p, h, o),
    post: (p, h, o) => add('POST', p, h, o),
    put: (p, h, o) => add('PUT', p, h, o),
    del: (p, h, o) => add('DELETE', p, h, o),
    match(method, path) {
      for (const r of routes) {
        if (r.method !== method) continue;
        const m = r.rx.exec(path);
        if (!m) continue;
        const params = {};
        r.keys.forEach((k, i) => { params[k] = decodeURIComponent(m[i + 1]); });
        return { handler: r.handler, params, public: r.public };
      }
      return null;
    },
  };
}
