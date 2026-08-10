import { cloudflareTest } from '@cloudflare/vitest-pool-workers';
import { defineConfig } from 'vitest/config';

// Workers の本物の実行環境で走らせる。Durable Object の一貫性が
// この仕組みの前提なので、模造品で試しても確かめたことにならない。
export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: './wrangler.jsonc' },
      miniflare: {
        bindings: {
          ANTHROPIC_API_KEY: 'test-api-key',
          APP_TOKEN: 'test-app-token',
          IP_SALT: 'test-salt',
          ADMIN_TOKEN: 'test-admin-token',
        },
      },
    }),
  ],
});
