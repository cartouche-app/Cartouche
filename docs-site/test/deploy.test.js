// deploy.sh against a stand-in for Cloudflare's API, for wrangler and for the
// documentation's address:
//
// - without the domain's token, the deploy does nothing;
// - it reads the zone's account, and runs wrangler deploy there, with the
//   token in wrangler's environment, never on a command line, and wrangler's
//   own usage measures off;
// - while the token may not deploy Workers, it warns with what to add to it,
//   and does not fail; any other failure of wrangler fails it;
// - the token is never printed;
// - it says whether the address gives the documentation, and warns when not.
//
// Run after `npm run build`, as deploy.sh needs dist/: npm test.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync, existsSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const DEPLOY = join(root, 'deploy.sh');
const TOKEN = 'domain-token-that-must-never-be-printed';
const ACCOUNT = 'c0ffee00c0ffee00c0ffee00c0ffee00';
const PERMISSIONS = 'add Account › Workers Scripts › Edit and Zone › Workers Routes › Edit';

// Cloudflare's API under /client/v4, and the documentation at /docs/.
async function standIn({ zone = true, page = [200, '<!doctype html><html lang="en"><title>Cartouche</title>'] } = {}) {
  const calls = [];
  const server = createServer((request, response) => {
    calls.push({ method: request.method, url: request.url, authorization: request.headers.authorization });
    if (request.url === '/docs/') {
      response.writeHead(page[0], { 'Content-Type': 'text/html' });
      return response.end(page[1]);
    }
    const answer =
      request.url === '/client/v4/zones?name=cartouche.cloud' && zone
        ? { success: true, errors: [], result: [{ id: 'z', name: 'cartouche.cloud', account: { id: ACCOUNT } }] }
        : { success: false, errors: [{ code: 9109, message: 'Unauthorized to access requested resource' }], result: null };
    response.writeHead(200, { 'Content-Type': 'application/json' });
    response.end(JSON.stringify(answer));
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  return { server, calls, base: `http://127.0.0.1:${server.address().port}` };
}

// A stand-in for npx: it writes down how wrangler was run, then prints and
// exits as the test asks.
function fakeNpx(dir, { output = 'Deployed cartouche-docs', status = 0 } = {}) {
  const record = join(dir, 'npx.json');
  const script = join(dir, 'npx');
  writeFileSync(
    script,
    `#!/usr/bin/env bash
node -e 'require("fs").writeFileSync(process.argv[1], JSON.stringify({args: process.argv.slice(2), token: process.env.CLOUDFLARE_API_TOKEN, account: process.env.CLOUDFLARE_ACCOUNT_ID, metrics: process.env.WRANGLER_SEND_METRICS, cwd: process.cwd()}))' ${JSON.stringify(record)} "$@"
printf '%s\\n' ${JSON.stringify(output)}
exit ${status}
`,
  );
  chmodSync(script, 0o755);
  return record;
}

// Run asynchronously: the stand-in answers from this same process.
function deploy(base, dir, env = {}) {
  const child = spawn('bash', [DEPLOY], {
    env: {
      PATH: `${dir}:${process.env.PATH}`,
      HOME: dir,
      CLOUDFLARE_API: `${base}/client/v4`,
      CARTOUCHE_DOCS_ADDRESS: `${base}/docs/`,
      CARTOUCHE_DOCS_TRIES: '1',
      GITHUB_STEP_SUMMARY: join(dir, 'summary.md'),
      NO_PROXY: '127.0.0.1',
      no_proxy: '127.0.0.1',
      ...env,
    },
  });
  let stdout = '';
  let stderr = '';
  child.stdout.on('data', (chunk) => (stdout += chunk));
  child.stderr.on('data', (chunk) => (stderr += chunk));
  return new Promise((resolve) => child.on('close', (status) => resolve({ status, stdout, stderr })));
}

async function withStandIn(options, check) {
  const dir = mkdtempSync(join(tmpdir(), 'docs-deploy-'));
  const stand = await standIn(options.cloudflare);
  try {
    await check(stand, dir);
  } finally {
    stand.server.close();
    rmSync(dir, { recursive: true, force: true });
  }
}

test('the deploy needs the build', () => {
  assert.ok(existsSync(join(root, 'dist', 'index.html')), 'run npm run build first');
});

test('without the token it does nothing', async () => {
  await withStandIn({}, async (stand, dir) => {
    const record = fakeNpx(dir);
    const run = await deploy(stand.base, dir, { CLOUDFLARE_DOMAIN_TOKEN: '' });
    assert.equal(run.status, 0);
    assert.match(run.stdout, /No CLOUDFLARE_DOMAIN_TOKEN/);
    assert.equal(stand.calls.length, 0);
    assert.ok(!existsSync(record));
  });
});

test('it deploys with wrangler in the zone\'s account, and checks the address', async () => {
  await withStandIn({}, async (stand, dir) => {
    const record = fakeNpx(dir);
    const run = await deploy(stand.base, dir, { CLOUDFLARE_DOMAIN_TOKEN: TOKEN });
    assert.equal(run.status, 0, run.stderr);
    const wrangler = JSON.parse(readFileSync(record, 'utf8'));
    assert.deepEqual(wrangler.args, ['--no-install', 'wrangler', 'deploy']);
    assert.equal(wrangler.token, TOKEN);
    assert.equal(wrangler.account, ACCOUNT);
    assert.equal(wrangler.metrics, 'false');
    assert.equal(wrangler.cwd, root);
    assert.equal(stand.calls[0].authorization, `Bearer ${TOKEN}`);
    assert.match(run.stdout, /gives the documentation/);
    assert.ok(!run.stdout.includes(TOKEN) && !run.stderr.includes(TOKEN), 'the token was printed');
    assert.match(readFileSync(join(dir, 'summary.md'), 'utf8'), /The documentation: /);
  });
});

test('a token that may not deploy Workers yet warns, and does not fail', async () => {
  await withStandIn({}, async (stand, dir) => {
    fakeNpx(dir, { output: '✘ [ERROR] A request to the Cloudflare API failed. Authentication error [code: 10000]', status: 1 });
    const run = await deploy(stand.base, dir, { CLOUDFLARE_DOMAIN_TOKEN: TOKEN });
    assert.equal(run.status, 0, run.stderr);
    assert.match(run.stdout, /::warning::/);
    assert.ok(run.stdout.includes(PERMISSIONS));
  });
});

test('any other failure of wrangler fails the deploy', async () => {
  await withStandIn({}, async (stand, dir) => {
    fakeNpx(dir, { output: '✘ [ERROR] Something else went wrong', status: 1 });
    const run = await deploy(stand.base, dir, { CLOUDFLARE_DOMAIN_TOKEN: TOKEN });
    assert.equal(run.status, 1);
    assert.match(run.stderr, /could not deploy/);
  });
});

test('a token that does not see the zone fails before wrangler', async () => {
  await withStandIn({ cloudflare: { zone: false } }, async (stand, dir) => {
    const record = fakeNpx(dir);
    const run = await deploy(stand.base, dir, { CLOUDFLARE_DOMAIN_TOKEN: TOKEN });
    assert.equal(run.status, 1);
    assert.match(run.stderr, /9109/);
    assert.ok(!existsSync(record));
  });
});

test('an address that does not answer yet warns', async () => {
  await withStandIn({ cloudflare: { page: [522, 'origin'] } }, async (stand, dir) => {
    fakeNpx(dir);
    const run = await deploy(stand.base, dir, { CLOUDFLARE_DOMAIN_TOKEN: TOKEN });
    assert.equal(run.status, 0, run.stderr);
    assert.match(run.stdout, /::warning::.*does not give the documentation yet \(HTTP 522\)/);
  });
});
