# web/

The frontend. Anything that builds to static files works; the
[Frontend workflow](../.github/workflows/deploy-frontend.yml) handles both cases:

- **With `package.json`:** CI runs `npm ci`, `lint`/`test` if defined, then
  `npm run build`, and publishes `web/dist/`. Put content-hashed files under
  `dist/assets/` (Vite's default) to get year-long caching.
- **Without:** `web/` is published as plain static files (the current
  placeholder).

## Runtime config

Don't bake environment values into the build. The deploy writes `/config.js`:

```js
window.__WARDROBE_CONFIG__ = {
  env: "dev",
  cognito: { region, userPoolId, clientId, domain }, // Hosted UI, Authorization Code + PKCE
  apiBaseUrl: "https://....execute-api.us-east-1.amazonaws.com"
};
```

Load it before the app (`<script src="/config.js"></script>` in `index.html`).
CloudFront serves `index.html` for unknown paths, so client-side routing works
on deep links. For local development, copy a `config.js` from a deployed env
(`curl https://<frontend_domain>/config.js`) and add `http://localhost:<port>`
to `app_origins` / `auth_callback_urls` in `infra/envs/dev/ci.auto.tfvars`.
