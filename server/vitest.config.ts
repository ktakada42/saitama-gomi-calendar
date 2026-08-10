import { cloudflareTest } from '@cloudflare/vitest-pool-workers';
import { defineConfig } from 'vitest/config';

// Workers の本物の実行環境で走らせる。Durable Object の一貫性が
// この仕組みの前提なので、模造品で試しても確かめたことにならない。
export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: './wrangler.jsonc' },
      // Workers AI には手元での代役が無いので、既定では本物に繋ぎにいく。
      // それだとテストにCloudflareの資格情報が要るうえ、CIから外に出て
      // 課金もされる。ここは切って、テスト側で AI を差し替える。
      remoteBindings: false,
      miniflare: {
        bindings: {
          APP_TOKEN: 'test-app-token',
          IP_SALT: 'test-salt',
          ADMIN_TOKEN: 'test-admin-token',
        },
      },
    }),
  ],
});
