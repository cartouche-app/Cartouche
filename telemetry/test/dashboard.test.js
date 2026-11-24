// Tests of the telemetry dashboard (telemetry/dashboard/): its Worker, which
// opens only behind Cloudflare Access and reads the database a page at a
// time, and what its page sums up (index.html's model), on the reports
// Cartouche makes (app-reports.json) as the telemetry server keeps them, and
// on the page's sample data.
//
//     node --import ./telemetry/test/text-modules.mjs --test telemetry/test/dashboard.test.js

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { afterEach, beforeEach, test } from "node:test";
import vm from "node:vm";

import dashboard, {
  CLOSED,
  LIMITS,
  REPORT,
  SESSION,
  SQL,
  data,
  daysAsked,
  forgetAccessKeys,
  problemsOnGitHub,
  teamDomain,
  verifyAccessToken,
  viewer,
} from "../dashboard/worker.js";
import telemetry, { resetThrottle } from "../worker.js";

const PAGE = readFileSync(new URL("../dashboard/index.html", import.meta.url), "utf8");
const SCHEMA_SQL = readFileSync(new URL("../schema.sql", import.meta.url), "utf8");
const APP_REPORTS = JSON.parse(readFileSync(new URL("./app-reports.json", import.meta.url), "utf8")).reports;
const BUILDER_REPORTS = JSON.parse(readFileSync(new URL("./builder-reports.json", import.meta.url), "utf8")).reports;

// The page's model, run as the browser runs it, here.
const MODEL = /<script nonce="\{\{nonce\}\}" id="model">([\s\S]*?)<\/script>/.exec(PAGE)[1];
vm.runInThisContext(MODEL);
const M = globalThis.CartoucheModel;

const NOW = Date.UTC(2026, 10, 10, 9, 30);
const TODAY = "2026-11-10";
const TEAM = "https://cartouche.cloudflareaccess.com";
const AUD = "4714c1358e65fe4b408ad6d432a5f878f08194bdb4752441fd56faefa9b2b6f2";
const SIGNED_IN = { access: { aud: AUD, getIdentity: async () => ({ email: "player@example.com" }) } };

let realFetch;
beforeEach(() => {
  realFetch = globalThis.fetch;
  forgetAccessKeys();
});
afterEach(() => {
  globalThis.fetch = realFetch;
});

function get(path, headers = {}) {
  return new Request(`https://cartouche-dashboard.example.workers.dev${path}`, { headers });
}

// MARK: A stand-in for D1

// The reports as the page query answers them: newest first, as rows of
// the dashboard's columns, the way D1 writes them (test_dashboard.py
// checks the SQL itself on SQLite).
class PagedD1 {
  constructor(count = 0) {
    this.rows = Array.from({ length: count }, (_, index) => ({
      rowid: index + 1,
      day: TODAY,
      row: ["event", TODAY, "8c1f6c2e", index + 1, "iPhone19,4", "27.3", "0.10.0", "fr", 6143, true, null, "app.opened", { games: 3 }],
    }));
    this.received = [{ day: TODAY, reports: 12, installs: 2 }, { day: "2026-11-09", reports: 30, installs: 3 }];
    this.problems = { waiting: 1, today: 2 };
    this.largest = Infinity;
    this.down = false;
    this.calls = [];
  }

  prepare(sql) {
    return { bind: (...args) => ({ sql, args, all: () => this.answer(sql, args) }) };
  }

  async batch(statements) {
    const answers = [];
    for (const statement of statements) answers.push(await this.answer(statement.sql, statement.args));
    return answers;
  }

  async answer(sql, args) {
    this.calls.push(sql);
    if (this.down) throw new Error("D1 is away");
    switch (sql) {
      case SQL.first: {
        const found = this.rows.filter((row) => row.day >= args[0])[0];
        return { results: found ? [{ first: found.rowid }] : [], meta: { rows_read: found ? 1 : 0 } };
      }
      case SQL.received:
        return { results: this.received.filter((row) => row.day >= args[0]), meta: { rows_read: 5 } };
      case SQL.problems:
        return { results: [this.problems], meta: { rows_read: 3, size_after: 524288 } };
      case SQL.page: {
        const [lowest, below, size, from] = args;
        if (size > this.largest) throw new Error("D1_ERROR: string or blob too big: SQLITE_TOOBIG");
        const page = this.rows
          .filter((row) => row.rowid >= lowest && row.rowid < below && row.day >= from)
          .sort((a, b) => b.rowid - a.rowid)
          .slice(0, size);
        return {
          results: [{ rows: JSON.stringify(page.map((row) => row.row)), next: page.length ? page[page.length - 1].rowid : null, n: page.length }],
          meta: { rows_read: page.length, size_after: 1048576 },
        };
      }
      default:
        throw new Error(`a statement the dashboard does not make: ${sql}`);
    }
  }
}

// MARK: Cloudflare Access

test("without Cloudflare Access, the page says it is closed and no data leaves", async () => {
  const db = new PagedD1(3);
  const env = { DB: db };
  const page = await dashboard.fetch(get("/"), env, {}, NOW);
  assert.equal(page.status, 403);
  const text = await page.text();
  assert.match(text, /Ce tableau de bord est fermé/);
  assert.doesNotMatch(text, /\{\{nonce\}\}/);
  assert.match(page.headers.get("content-security-policy"), /script-src 'nonce-[A-Za-z0-9_-]{24}'/);
  const answer = await dashboard.fetch(get("/data"), env, {}, NOW);
  assert.equal(answer.status, 403);
  assert.equal(answer.headers.get("content-type"), "application/json; charset=utf-8");
  assert.deepEqual(await answer.json(), { error: "Cloudflare Access did not sign this request in" });
  assert.equal(db.calls.length, 0);
});

test("a header that looks like Access's is not enough", async () => {
  const env = { DB: new PagedD1(1) };
  const forged = await dashboard.fetch(get("/data", { "cf-access-authenticated-user-email": "player@example.com", "cf-access-jwt-assertion": "a.b.c" }), env, {}, NOW);
  assert.equal(forged.status, 403);
});

test("signed in by Access, the page and its data open", async () => {
  const env = { DB: new PagedD1(2) };
  const page = await dashboard.fetch(get("/"), env, SIGNED_IN, NOW);
  assert.equal(page.status, 200);
  const text = await page.text();
  const csp = page.headers.get("content-security-policy");
  const nonce = /script-src 'nonce-([^']+)'/.exec(csp)[1];
  assert.match(csp, new RegExp(`style-src 'nonce-${nonce}'`));
  assert.match(csp, /img-src 'self' data: https:\/\/images\.igdb\.com;/);
  assert.match(csp, /connect-src 'self';/);
  assert.match(csp, /frame-ancestors 'none'/);
  assert.equal(text.split(`nonce="${nonce}"`).length - 1, 3);
  assert.doesNotMatch(text, /\{\{nonce\}\}/);
  for (const [name, value] of [["cache-control", "no-store"], ["x-frame-options", "DENY"], ["x-robots-tag", "noindex, nofollow"], ["referrer-policy", "no-referrer"]]) {
    assert.equal(page.headers.get(name), value, name);
  }
  const answer = await dashboard.fetch(get("/data?days=7"), env, SIGNED_IN, NOW);
  assert.equal(answer.status, 200);
  const body = await answer.json();
  assert.equal(body.viewer, "player@example.com");
  assert.equal(body.days, 7);
  assert.equal(body.from, "2026-11-04");
});

test("each page gets a nonce of its own", async () => {
  const env = { DB: new PagedD1() };
  const nonces = new Set();
  for (let index = 0; index < 3; index += 1) {
    const page = await dashboard.fetch(get("/"), env, SIGNED_IN, NOW);
    nonces.add(/'nonce-([^']+)'/.exec(page.headers.get("content-security-policy"))[1]);
  }
  assert.equal(nonces.size, 3);
});

test("Access's identity out of reach still signs in, without an address", async () => {
  const who = await viewer(get("/"), {}, { access: { aud: AUD, getIdentity: async () => { throw new Error("no identity"); } } }, NOW);
  assert.deepEqual(who, { email: null });
});

test("only GET, on the page and its data", async () => {
  const env = { DB: new PagedD1() };
  const post = await dashboard.fetch(new Request("https://cartouche-dashboard.example.workers.dev/data", { method: "POST", body: "{}" }), env, SIGNED_IN, NOW);
  assert.equal(post.status, 405);
  const other = await dashboard.fetch(get("/v1/reports"), env, SIGNED_IN, NOW);
  assert.equal(other.status, 404);
});

test("the team's address, from its name or its address, and nothing else", () => {
  for (const value of ["cartouche", "Cartouche", "cartouche.cloudflareaccess.com", "https://cartouche.cloudflareaccess.com", "https://cartouche.cloudflareaccess.com/", " cartouche "]) {
    assert.equal(teamDomain(value), TEAM, value);
  }
  for (const value of ["", "evil.example.com", "https://cartouche.cloudflareaccess.com.evil.example", "http://cartouche.cloudflareaccess.com", "-cartouche", "car touche", undefined, null, 7]) {
    assert.equal(teamDomain(value), undefined, String(value));
  }
});

// The tokens of Access's: RS256, signed with a key of the team's certs.
const base64url = (value) => Buffer.from(value).toString("base64url");
async function team(kid = "key-1") {
  const pair = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  );
  const jwk = await crypto.subtle.exportKey("jwk", pair.publicKey);
  return { pair, key: { kid, kty: "RSA", alg: "RS256", use: "sig", e: jwk.e, n: jwk.n } };
}
async function token(pair, claims = {}, header = {}) {
  const head = base64url(JSON.stringify({ alg: "RS256", kid: "key-1", typ: "JWT", ...header }));
  const body = base64url(
    JSON.stringify({ iss: TEAM, aud: [AUD], email: "player@example.com", sub: "1", iat: NOW / 1000, nbf: NOW / 1000, exp: NOW / 1000 + 3600, ...claims }),
  );
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", pair.privateKey, new TextEncoder().encode(`${head}.${body}`));
  return `${head}.${body}.${base64url(new Uint8Array(signature))}`;
}
function certs(...keys) {
  const fetched = [];
  globalThis.fetch = async (url) => {
    fetched.push(String(url));
    if (String(url) === `${TEAM}/cdn-cgi/access/certs`) return Response.json({ keys });
    return new Response("", { status: 404 });
  };
  return fetched;
}
const ENV = { ACCESS_TEAM_DOMAIN: "cartouche", ACCESS_AUD: AUD };

test("behind a hostname's Access application, its token signs in", async () => {
  const { pair, key } = await team();
  const fetched = certs(key);
  const env = { ...ENV, DB: new PagedD1(1) };
  const answer = await dashboard.fetch(get("/data", { "cf-access-jwt-assertion": await token(pair) }), env, {}, NOW);
  assert.equal(answer.status, 200);
  assert.equal((await answer.json()).viewer, "player@example.com");
  assert.deepEqual(fetched, [`${TEAM}/cdn-cgi/access/certs`]);
  // The keys stay known.
  await dashboard.fetch(get("/data", { "cf-access-jwt-assertion": await token(pair) }), env, {}, NOW + 1000);
  assert.equal(fetched.length, 1);
});

test("a token of another application, another team, out of its time or not signed by the team is refused", async () => {
  const { pair, key } = await team();
  const other = await team();
  certs(key);
  const refused = [
    await token(pair, { aud: ["0".repeat(64)] }),
    await token(pair, { iss: "https://other.cloudflareaccess.com" }),
    await token(pair, { exp: NOW / 1000 - LIMITS.leeway - 1 }),
    await token(pair, { exp: undefined }),
    await token(pair, { nbf: NOW / 1000 + LIMITS.leeway + 60 }),
    await token(other.pair),
    await token(pair, {}, { alg: "HS256" }),
    await token(pair, {}, { alg: "none" }),
    (await token(pair)).replace(/\.[^.]+\./, `.${base64url(JSON.stringify({ iss: TEAM, aud: [AUD], email: "someone@example.com", exp: NOW / 1000 + 3600 }))}.`),
    "not.a.token",
    "",
    "x".repeat(20000),
  ];
  for (const [index, value] of refused.entries()) {
    assert.equal(await verifyAccessToken(value, TEAM, AUD, NOW), undefined, `token ${index}`);
  }
  assert.ok(await verifyAccessToken(await token(pair, { aud: AUD }), TEAM, AUD, NOW), "aud as a string");
});

test("without the team and the application, a token is not read", async () => {
  const { pair, key } = await team();
  const fetched = certs(key);
  const signed = await token(pair);
  for (const env of [{}, { ACCESS_TEAM_DOMAIN: "cartouche" }, { ACCESS_AUD: AUD }, { ACCESS_TEAM_DOMAIN: "evil.example.com", ACCESS_AUD: AUD }, { ACCESS_TEAM_DOMAIN: "cartouche", ACCESS_AUD: "short" }]) {
    assert.equal(await viewer(get("/", { "cf-access-jwt-assertion": signed }), env, {}, NOW), undefined);
  }
  assert.equal(fetched.length, 0);
});

test("a key the team signs with anew is fetched, at most once a minute", async () => {
  const first = await team("key-1");
  const second = await team("key-2");
  const fetched = certs(first.key);
  assert.ok(await verifyAccessToken(await token(first.pair), TEAM, AUD, NOW));
  const rotated = await token(second.pair, {}, { kid: "key-2" });
  assert.equal(await verifyAccessToken(rotated, TEAM, AUD, NOW + 1000), undefined);
  assert.equal(fetched.length, 1);
  certs(first.key, second.key);
  assert.ok(await verifyAccessToken(rotated, TEAM, AUD, NOW + 61000));
});

test("Access's keys out of reach sign nobody in", async () => {
  const { pair } = await team();
  globalThis.fetch = async () => {
    throw new TypeError("fetch failed");
  };
  assert.equal(await verifyAccessToken(await token(pair), TEAM, AUD, NOW), undefined);
});

// MARK: The data

test("the days asked, from 1 to 400, 28 without asking", () => {
  const days = (query) => daysAsked(new URL(`https://dashboard.example/data${query}`));
  assert.equal(days(""), 28);
  assert.equal(days("?days=7"), 7);
  assert.equal(days("?days=365"), 365);
  assert.equal(days("?days=0"), 1);
  assert.equal(days("?days=9999"), LIMITS.days);
  for (const query of ["?days=", "?days=abc", "?days=-3", "?days=1e3", "?days=12345", "?days=7.5"]) assert.equal(days(query), 28, query);
});

test("the reports go a page at a time, newest first, as D1 wrote them", async () => {
  const db = new PagedD1(4500);
  const text = await data({ DB: db }, { email: "player@example.com" }, NOW, 28);
  const body = JSON.parse(text);
  assert.equal(body.count, 4500);
  assert.equal(body.truncated, false);
  assert.equal(body.reports.length, 4500);
  assert.deepEqual(body.reports.slice(0, 2).map((row) => row[3]), [4500, 4499]);
  assert.equal(body.reports.at(-1)[3], 1);
  assert.deepEqual(body.columns, { report: REPORT, session: SESSION });
  assert.deepEqual(body.received, { today: 12, yesterday: 30, installsToday: 2 });
  assert.deepEqual({ waiting: body.problems.waiting, today: body.problems.today, github: body.problems.github }, { waiting: 1, today: 2, github: null });
  assert.deepEqual(body.database, { bytes: 1048576, rowsRead: 1 + 5 + 3 + 4500 });
  assert.equal(db.calls.filter((sql) => sql === SQL.page).length, 3);
  assert.equal(body.generated, new Date(NOW).toISOString());
});

test("a window without reports sends none", async () => {
  const body = JSON.parse(await data({ DB: new PagedD1(0) }, null, NOW, 28));
  assert.equal(body.count, 0);
  assert.deepEqual(body.reports, []);
  assert.equal(body.viewer, null);
});

test("past the queries of one request, the newest reports go, and the answer says it is cut", async () => {
  const saved = { ...LIMITS };
  try {
    LIMITS.page = 10;
    LIMITS.smallestPage = 2;
    const db = new PagedD1(10 * LIMITS.queries);
    const body = JSON.parse(await data({ DB: db }, null, NOW, 28));
    assert.equal(body.truncated, true);
    assert.equal(body.count, 10 * (LIMITS.queries - 3));
    assert.equal(body.reports[0][3], 10 * LIMITS.queries);
    assert.equal(db.calls.length, LIMITS.queries);
  } finally {
    Object.assign(LIMITS, saved);
  }
});

test("a page too long for D1 comes again in smaller pages, every report once", async () => {
  const db = new PagedD1(2600);
  db.largest = 600;
  const body = JSON.parse(await data({ DB: db }, null, NOW, 28));
  assert.equal(body.count, 2600);
  assert.equal(new Set(body.reports.map((row) => row[3])).size, 2600);
  assert.equal(body.truncated, false);
});

test("the database out of reach, the page is told to try again", async () => {
  const db = new PagedD1(10);
  db.down = true;
  const answer = await dashboard.fetch(get("/data"), { DB: db }, SIGNED_IN, NOW);
  assert.equal(answer.status, 503);
  assert.deepEqual(await answer.json(), { error: "The database cannot be read right now" });
  const tooLong = new PagedD1(10);
  tooLong.largest = 1;
  assert.equal((await dashboard.fetch(get("/data"), { DB: tooLong }, SIGNED_IN, NOW)).status, 503);
});

// MARK: Problems on GitHub

const REPOSITORY = "cartouche-app/cartouche-reports";
const GITHUB_TOKEN = "github_pat_for_the_tests";

test("the problems' issues come from GitHub without their bodies", async () => {
  const asked = [];
  globalThis.fetch = async (url, init) => {
    asked.push({ url: String(url), init });
    return Response.json({
      data: {
        repository: {
          open: { totalCount: 2 },
          closed: { totalCount: 5 },
          issues: { nodes: [{ number: 7, title: "Le jeu se ferme", state: "OPEN", createdAt: "2026-11-10T08:00:00Z", closedAt: null, url: "https://github.com/x/y/issues/7", comments: { totalCount: 1 }, labels: { nodes: [{ name: "bug" }] } }] },
        },
      },
    });
  };
  const found = await problemsOnGitHub({ PROBLEMS_REPOSITORY: REPOSITORY, PROBLEMS_TOKEN: GITHUB_TOKEN });
  assert.deepEqual(found, {
    repository: REPOSITORY,
    open: 2,
    closed: 5,
    issues: [{ number: 7, title: "Le jeu se ferme", state: "OPEN", created: "2026-11-10T08:00:00Z", closed: null, url: "https://github.com/x/y/issues/7", comments: 1, labels: ["bug"] }],
  });
  assert.equal(asked.length, 1);
  assert.equal(asked[0].url, "https://api.github.com/graphql");
  assert.equal(asked[0].init.headers.authorization, `Bearer ${GITHUB_TOKEN}`);
  const query = JSON.parse(asked[0].init.body);
  assert.doesNotMatch(query.query, /\bbody\b/);
  assert.deepEqual(query.variables, { owner: "cartouche-app", name: "cartouche-reports", count: LIMITS.issues });
});

test("without the token, or GitHub away, the page says so and the token never shows", async () => {
  let asked = 0;
  globalThis.fetch = async () => {
    asked += 1;
    return new Response("{}", { status: 401 });
  };
  assert.equal(await problemsOnGitHub({ PROBLEMS_REPOSITORY: REPOSITORY }), undefined);
  assert.equal(await problemsOnGitHub({ PROBLEMS_REPOSITORY: "not a repository", PROBLEMS_TOKEN: GITHUB_TOKEN }), undefined);
  assert.equal(asked, 0);
  const refused = await problemsOnGitHub({ PROBLEMS_REPOSITORY: REPOSITORY, PROBLEMS_TOKEN: GITHUB_TOKEN });
  assert.deepEqual(refused, { repository: REPOSITORY, error: "GitHub answered 401" });
  globalThis.fetch = async () => Response.json({ data: { repository: null } });
  assert.deepEqual(await problemsOnGitHub({ PROBLEMS_REPOSITORY: REPOSITORY, PROBLEMS_TOKEN: GITHUB_TOKEN }), {
    repository: REPOSITORY,
    error: "GitHub does not show this repository to the token",
  });
  globalThis.fetch = async () => {
    throw new TypeError("fetch failed");
  };
  const away = await problemsOnGitHub({ PROBLEMS_REPOSITORY: REPOSITORY, PROBLEMS_TOKEN: GITHUB_TOKEN });
  assert.deepEqual(away, { repository: REPOSITORY, error: "GitHub could not be reached" });
  const body = await data({ DB: new PagedD1(1), PROBLEMS_REPOSITORY: REPOSITORY, PROBLEMS_TOKEN: GITHUB_TOKEN }, null, NOW, 28);
  assert.doesNotMatch(body, new RegExp(GITHUB_TOKEN));
});

// MARK: The page

test("the page's scripts and styles run under its nonce only", () => {
  const tags = PAGE.match(/<(script|style)\b[^>]*>/g);
  for (const tag of tags) {
    if (tag.includes('type="application/json"')) continue;
    assert.match(tag, /nonce="\{\{nonce\}\}"/, tag);
  }
  assert.doesNotMatch(PAGE, /\son[a-z]+="/, "no inline handler, which the policy would block");
  assert.doesNotMatch(PAGE, /<(script|link)\b[^>]*\b(src|href)="https?:/, "no script or style from elsewhere");
  assert.equal(PAGE.split('<script type="application/json" id="catalog">{}</script>').length - 1, 1, "one place for the catalog");
});

test("the page shows every field of a session the Worker sends, in its order", () => {
  assert.deepEqual([...M.SHOWN], SESSION);
  const sample = M.demo(7, {}, NOW);
  assert.deepEqual([...sample.columns.report], REPORT);
});

// A report as the server keeps it, as a row of /data: what the page query
// makes of it on SQLite (test_dashboard.py).
function asRow(report) {
  const item = { ...report, install: report.install.slice(0, 8), day: TODAY };
  if (report.kind === "session") {
    const at = (path) => path.split(".").reduce((value, key) => (value && typeof value === "object" ? value[key] : undefined), report);
    for (const path of SESSION) item[path] = path === "session" ? report.session.slice(0, 8) : at(path);
  }
  return M.compact({ report: REPORT, session: SESSION }, item);
}
function answer(rows, extra = {}) {
  return { schema: 1, today: TODAY, from: "2026-10-14", days: 28, columns: { report: REPORT, session: SESSION }, count: rows.length, reports: rows, ...extra };
}
const CATALOG = {
  games: { "0400C3F00006E000": ["Mario Kart World", "co9abc"], "0100000000010000": ["Super Mario Odyssey", "co1mxf"] },
  aliases: { "0400C3F00006F000": "0400C3F00006E000" },
  devices: { "iPhone19,4": ["A20 Pro", 12] },
};

test("the page sums up the reports Cartouche makes", () => {
  const model = M.build(answer(APP_REPORTS.map(asRow).reverse()), CATALOG);
  const [session] = APP_REPORTS;
  assert.equal(model.totals.iphones, 1);
  assert.equal(model.totals.sessions, 1);
  assert.equal(model.totals.minutes, session.minutes);
  assert.equal(model.totals.cadence, session.fps.median / session.targetFps);
  assert.equal(model.games.length, 1);
  const [game] = model.games;
  assert.equal(game.id, "0400C3F00006E000");
  assert.equal(game.name, "Mario Kart World");
  assert.equal(game.cover, "co9abc");
  assert.equal(game.fps, session.fps.median);
  // The slowest 5% only from the reading of the log that takes pauses out.
  assert.equal(game.low5, session.reader >= M.SLOWEST_READER ? session.fps.low5 : null);
  assert.equal(game.peak, session.memory.peakMiB);
  assert.deepEqual(game.tightest, { peak: session.memory.peakMiB, limit: session.memoryLimitMiB, ratio: session.memory.peakMiB / session.memoryLimitMiB });
  assert.deepEqual(model.memory.byGame.map((item) => [item.id, item.peak, item.limit]), [["0400C3F00006E000", session.memory.peakMiB, session.memoryLimitMiB]]);
  assert.equal(game.build, session.nxnative);
  assert.equal(game.ends.crash, 1);
  assert.deepEqual(model.endings.crashes.map((crash) => [crash.signal, crash.pc, crash.lr, crash.cause, crash.count]), [[6, "__pthread_kill+0x8", "pthread_kill+0x10c", "gpuLost", 1]]);
  assert.deepEqual(model.endings.gpuLost, { count: 1, read: 1 });
  assert.deepEqual(model.fluidity.frameMs.map((item) => item.value), [session.frameMs.p50, session.frameMs.p95, session.frameMs.p99]);
  assert.deepEqual(model.fluidity.settings.map((item) => item.key), ["DM_OPMODE=0", "DM_RENDER_SCALE=1.0"]);
  assert.equal(model.fluidity.upscaler[0].key, "metalfx");
  assert.deepEqual(model.fluidity.fold, { share: 1, yes: 1, known: 1 });
  assert.deepEqual(model.heat.minutes.map((item) => item.minutes), [18, 9, 8.2, 0]);
  assert.equal(model.heat.watts, session.cpu.watts);
  assert.equal(model.memory.headroom, session.memory.lowestHeadroomMiB);
  assert.deepEqual(model.memory.increased, { share: 1, yes: 1, known: 1 });
  assert.equal(model.installs.count, 1);
  // Where it came from, and how the Mac was reached.
  assert.deepEqual(model.installs.from.map((item) => [item.key, item.count]), [["mac", 1]]);
  assert.deepEqual(model.devices.models.map((item) => item.key), ["iPhone19,4"]);
  assert.deepEqual(model.devices.languages.map((item) => item.key), ["fr"]);
  assert.deepEqual(model.devices.deviceLanguages.map((item) => item.key), ["fr"]);
  assert.deepEqual(model.eventNames.map((item) => item.key), ["game.installed"]);
  const day = model.daily.find((item) => item.day === TODAY);
  assert.deepEqual([day.iphones, day.sessions, day.bad], [1, 1, 1]);
  assert.equal(day.cadence, session.fps.median / session.targetFps);
});

test("a session sent again counts once, at its highest seq; a variant counts for its game", () => {
  const [session] = APP_REPORTS;
  const again = { ...session, seq: session.seq + 5, minutes: 50, game: "0400C3F00006F000" };
  const model = M.build(answer([asRow(again), asRow(session)]), CATALOG);
  assert.equal(model.totals.sessions, 1);
  assert.equal(model.totals.minutes, 50);
  assert.equal(model.games[0].id, "0400C3F00006E000");
});

test("Cartouche Builder's Macs are not iPhones", () => {
  const mac = { schema: 1, kind: "event", seq: 1, install: "0b1e2c3d-0000-4000-8000-000000000000", cartouche: "0.2.1", device: "Mac16,12", ios: "26.6", name: "builder.built", game: "0100000000010000", fields: { seconds: 3600, ipaMB: 2100, source: "dump", reasons: "named,shared" } };
  const model = M.build(answer([asRow(mac), ...APP_REPORTS.map(asRow)]), CATALOG);
  assert.equal(model.totals.iphones, 1);
  assert.equal(model.totals.macs, 1);
  assert.equal(model.builder.built.count, 1);
  assert.deepEqual(model.builder.built.reasons.map((item) => item.key), ["named", "shared"]);
  assert.equal(model.builder.built.games[0].name, "Super Mario Odyssey");
  assert.ok(!model.eventNames.some((item) => item.key.startsWith("builder.")));
});

test("the games played on a Mac are set apart from the iPhones', each Mac once", () => {
  // As Cartouche's console reads them in the log of nxnative's app for the Mac.
  const played = BUILDER_REPORTS.find((report) => report.kind === "session");
  const grown = { ...played, seq: played.seq + 3, minutes: 45 };
  const other = { ...played, install: "0b1e2c3d-0000-4000-8000-000000000000", session: "0f0f0f0f-0000-4000-8000-000000000001", device: "Mac15,9", minutes: 12, end: { kind: "crash", cause: "gpuLost" } };
  const opened = { schema: 1, kind: "event", seq: 1, install: played.install, cartouche: "0.2.1", device: "Mac16,12", ios: "26.6", name: "builder.opened", fields: { games: 3 } };
  const model = M.build(answer([asRow(grown), asRow(other), asRow(played), asRow(opened), ...APP_REPORTS.map(asRow)]), CATALOG);
  // Not an iPhone's: the iPhones' sections, filters and sums leave them out.
  assert.equal(model.totals.iphones, 1);
  assert.ok(model.games.every((game) => game.id !== played.game));
  assert.ok(model.options.games.every((item) => item.value !== played.game));
  assert.ok(model.options.devices.every((item) => !item.value.startsWith("Mac")));
  assert.equal(model.totals.sessions, APP_REPORTS.filter((report) => report.kind === "session").length);
  // Apart: the session read again once its log grew counts once, at its highest seq.
  assert.deepEqual(model.macPlay, { sessions: 2, macs: 2, minutes: 57 });
  const [game] = model.macGames;
  assert.equal(game.id, played.game);
  assert.equal(game.macs, 2);
  assert.equal(game.sessions, 2);
  assert.equal(game.minutes, 57);
  assert.equal(game.ends.ok, 1);
  assert.equal(game.ends.crash, 1);
  assert.equal(game.gpuLost, 1);
  assert.equal(game.fps, played.fps.median);
  assert.equal(game.target, 60);
  assert.deepEqual([...game.models].sort(), ["Mac15,9", "Mac16,12"]);
  assert.equal(game.build, played.nxnative);
  assert.equal(game.verdict.status, "boots", "one of two ended badly");
  assert.equal(model.totals.reports, APP_REPORTS.length + 1 + 2);
  // A game picked filters them too.
  assert.equal(M.build(answer([asRow(played), ...APP_REPORTS.map(asRow)]), CATALOG, { game: "0400C3F00006E000" }).macGames.length, 0);
});

test("the filters scope everything to a game, a model or a version", () => {
  const [session, event] = APP_REPORTS;
  const other = { ...session, session: "0f0f0f0f-0000-4000-8000-000000000000", install: "11111111-2222-4333-8444-555555555555", device: "iPhone18,1", game: "0100000000010000", minutes: 10, end: undefined };
  const rows = answer([asRow(other), asRow(session), asRow(event)]);
  const all = M.build(rows, CATALOG);
  assert.equal(all.totals.iphones, 2);
  assert.deepEqual(all.options.games.map((item) => item.value).sort(), ["0100000000010000", "0400C3F00006E000"]);
  const odyssey = M.build(rows, CATALOG, { game: "0100000000010000" });
  assert.equal(odyssey.totals.sessions, 1);
  assert.equal(odyssey.totals.iphones, 1);
  assert.equal(odyssey.installs.count, 0, "the other iPhone's install is of another game");
  assert.equal(odyssey.endings.ends.ok, 1);
  const model = M.build(rows, CATALOG, { device: "iPhone19,4" });
  assert.deepEqual(model.games.map((game) => game.id), ["0400C3F00006E000"]);
  assert.equal(M.build(rows, CATALOG, { version: "0.9.0" }).totals.reports, 0);
});

test("a game's memory is read against the limit of the iPhone it ran on", () => {
  const [session] = APP_REPORTS;
  const roomy = { ...session, memory: { ...session.memory, peakMiB: 5000 } };
  // In Cartouche's place: its limit is the iPhone's.
  const tight = { ...session, session: "0f0f0f0f-0000-4000-8000-000000000000", install: "11111111-2222-4333-8444-555555555555", memoryLimitMiB: 3376, increasedMemoryLimit: false, memory: { ...session.memory, peakMiB: 3000 }, process: undefined };
  const model = M.build(answer([asRow(roomy), asRow(tight)]), CATALOG);
  const [game] = model.games;
  assert.equal(game.peak, 5000);
  assert.deepEqual(game.tightest, { peak: 3000, limit: 3376, ratio: 3000 / 3376 });
  assert.deepEqual(model.memory.limits.map((item) => [item.key, item.count]), [[3376, 1], [6143, 1]]);
});

test("a game that ran behind the console is read against its process's limit, and one the player quit ended well", () => {
  const [session] = APP_REPORTS;
  const behind = { ...session, process: { ...session.process, limitMiB: 5120, quit: true }, end: { kind: "quit" } };
  const model = M.build(answer([asRow(behind)]), CATALOG);
  const [game] = model.games;
  assert.deepEqual(game.tightest, { peak: session.memory.peakMiB, limit: 5120, ratio: session.memory.peakMiB / 5120 });
  assert.equal(game.ends.ok, 1);
  assert.equal(game.ends.bad, 0);
});

test("a limit below the game's peak was not its own, and is not the one it came closest to", () => {
  const [session] = APP_REPORTS;
  // In 0.12, a game behind the console sent Cartouche's limit, below the game's own peak.
  const behind = { ...session, process: { ...session.process, limitMiB: 3376 } };
  const own = { ...session, session: "0f0f0f0f-0000-4000-8000-000000000000", memory: { ...session.memory, peakMiB: 5000 }, process: undefined };
  const [game] = M.build(answer([asRow(behind), asRow(own)]), CATALOG).games;
  assert.equal(game.peak, 5000);
  assert.deepEqual(game.tightest, { peak: 5000, limit: 6143, ratio: 5000 / 6143 });
  // Past every limit it sent, a game came close to none.
  assert.equal(M.build(answer([asRow(behind)]), CATALOG).games[0].tightest, null);
});

test("errors by version of Cartouche, against its openings, the newest version first", () => {
  const [, event] = APP_REPORTS;
  const opened = (cartouche, seq) => ({ ...event, cartouche, seq, name: "app.opened", game: undefined, fields: { games: 2 } });
  const error = (cartouche, seq) => ({ ...event, cartouche, seq, name: "error", game: undefined, fields: { origin: "storage", error: "NSPOSIXErrorDomain 60", background: true } });
  const rows = [opened("0.9.0", 1), error("0.9.0", 2), opened("0.10.0", 3), opened("0.10.0", 4), error("0.10.0", 5)].map(asRow);
  const model = M.build(answer(rows), CATALOG);
  assert.deepEqual(model.errors.byVersion, [{ version: "0.10.0", errors: 1, opens: 2 }, { version: "0.9.0", errors: 1, opens: 1 }]);
  assert.deepEqual(model.errors.byCode.map((row) => [row.origin, row.error, row.count]), [["storage", "NSPOSIXErrorDomain 60", 2]]);
  assert.deepEqual(["0.9.0", "0.10.0", "0.10.1", "1.0"].sort(M.newestFirst), ["1.0", "0.10.1", "0.10.0", "0.9.0"]);
});

test("the Apple sign-in says how often it goes through, the step it stops at and why", () => {
  const [, event] = APP_REPORTS;
  const failed = (seq, stage, cause, vpn) => ({ ...event, seq, name: "error", game: undefined, fields: { origin: "signIn", error: "SideStore 1", cause, stage, kind: "noDevice", vpn, pairing: true, seconds: 20 } });
  const signedIn = (seq) => ({ ...event, seq, name: "account.signedIn", game: undefined, fields: { seconds: 12, automatic: false } });
  const rows = [failed(1, "device", "device", false), failed(2, "device", "device", false), failed(3, "team", "appleServer", true), signedIn(4)].map(asRow);
  const model = M.build(answer(rows), CATALOG);
  const signIn = model.errors.signIn;
  assert.deepEqual([signIn.succeeded, signIn.failed, signIn.iphones], [1, 3, 1]);
  assert.deepEqual(signIn.byStage.map((row) => [row.key, row.count]), [["device", 2], ["team", 1]]);
  assert.deepEqual(model.errors.byCause.map((row) => [row.key, row.count]), [["device", 2], ["appleServer", 1]]);
  assert.deepEqual(signIn.vpn, { share: 1 / 3, yes: 1, known: 3 });
  assert.deepEqual([signIn.seconds, signIn.secondsOk], [20, 12]);
  assert.deepEqual(model.errors.byCode.map((row) => [row.cause, row.stage, row.kind, row.count]), [["device", "device", "noDevice", 2], ["appleServer", "team", "noDevice", 1]]);
  // An error from before the causes says none.
  const older = M.build(answer([asRow({ ...event, seq: 9, name: "error", game: undefined, fields: { origin: "storage", error: "NSPOSIXErrorDomain 60" } })]), CATALOG);
  assert.deepEqual(older.errors.byCause.map((row) => row.key), ["unknown"]);
});

// MARK: What the page makes of the reports

// Reports of copies of their own, number N (the server keeps the first 8
// characters of an install and of a session).
let serial = 0;
const copy = (n) => `${String(n).padStart(8, "0")}-0000-4000-8000-000000000000`;
function sessionOf(n, fields = {}) {
  serial += 1;
  const [session] = APP_REPORTS;
  return { ...session, install: copy(n), session: `${String(serial).padStart(8, "0")}-1111-4000-8000-000000000000`, seq: serial, end: undefined, ...fields };
}
function eventOf(n, name, fields = {}, extra = {}) {
  serial += 1;
  const [, event] = APP_REPORTS;
  return { ...event, install: copy(n), seq: serial, name, game: undefined, fields, ...extra };
}
function onDay(day, report) {
  const row = asRow(report);
  row[REPORT.indexOf("day")] = day;
  return row;
}
const build = (reports) => M.build(answer(reports.map((report) => (Array.isArray(report) ? report : asRow(report)))), CATALOG);

test("the slowest 5% counts only from the reading of the log that takes pauses out", () => {
  assert.equal(M.SLOWEST_READER, 2);
  // Read before, a pause took this session's slowest 5% down to 12 frames a second.
  const before = sessionOf(1, { reader: 1, fps: { median: 59.9, low5: 12 } });
  const after = sessionOf(2, { reader: 2, fps: { median: 59.9, low5: 50 } });
  const model = build([before, after]);
  const [game] = model.games;
  assert.equal(game.low5, 50);
  assert.equal(game.low5Waiting, 1);
  assert.deepEqual([model.fluidity.low5, model.fluidity.low5Measured, model.fluidity.low5Waiting], [50, 1, 1]);
  assert.equal(game.verdict.status, "playable", "the pause makes no game « with issues »");
  const older = build([before]);
  assert.equal(older.games[0].low5, null);
  assert.equal(older.fluidity.low5, null);
  assert.equal(older.games[0].verdict.status, "playable");
});

test("the Duo's fold counts only from the reading of the log that ties it to the fold", () => {
  assert.equal(M.FOLD_READER, 3);
  // Read before, any iPhone upright said its picture and its controls were apart.
  const before = sessionOf(1, { reader: 2, display: { tv: false, foldSplit: true } });
  const upright = sessionOf(2, { reader: 3, display: { tv: false, foldSplit: false } });
  const unfolded = sessionOf(3, { reader: 3, display: { tv: false, foldSplit: true } });
  assert.deepEqual(build([before, upright, unfolded]).fluidity.fold, { share: 0.5, yes: 1, known: 2 });
  assert.equal(build([before]).fluidity.fold, null);
});

test("a lost GPU is a crash of its own, counted from the reading of the log that tells it", () => {
  assert.equal(M.GPU_LOST_READER, 4);
  const abort = { kind: "crash", signal: 6, pc: "__pthread_kill+0x8", lr: "pthread_kill+0x10c" };
  const lost = sessionOf(1, { reader: 4, end: { ...abort, cause: "gpuLost" } });
  // A Mac quits the game itself: no signal.
  const onMac = sessionOf(2, { reader: 4, end: { kind: "crash", cause: "gpuLost" } });
  const other = sessionOf(3, { reader: 4, end: abort });
  // Read before, a lost GPU was an abort like this one.
  const before = sessionOf(4, { reader: 3, end: abort });
  const model = build([lost, onMac, other, before]);
  assert.equal(model.endings.ends.crash, 4);
  assert.deepEqual(model.endings.gpuLost, { count: 2, read: 3 });
  assert.deepEqual(
    model.endings.crashes.map((crash) => [crash.signal, crash.cause, crash.count]).sort((a, b) => String(a).localeCompare(String(b))),
    [[6, "gpuLost", 1], [6, null, 2], [null, "gpuLost", 1]].sort((a, b) => String(a).localeCompare(String(b))),
  );
  assert.deepEqual(build([before]).endings.gpuLost, { count: 0, read: 0 });
});

test("a crash in the game's code goes by its address; an abort, whose address is the system's, by its game", () => {
  assert.ok(["main+0x8903c8", "sdk+0x2c10", "subsdk1+0x10", "rtld+0x4"].every((pc) => M.GAME_CODE.test(pc)));
  assert.ok(!["__pthread_kill+0x8", "objc_exception_throw+0x3c"].some((pc) => M.GAME_CODE.test(pc)));
  const smo = "0100000000010000";
  const segv = { kind: "crash", signal: 11, pc: "main+0x8903c8", lr: "main+0x8903bc" };
  const abort = { kind: "crash", signal: 6, pc: "__pthread_kill+0x8", lr: "pthread_kill+0x10c" };
  const { crashes } = build([
    // The same address in the game's code, in two games on two iPhones: one bug.
    sessionOf(1, { end: segv }),
    sessionOf(2, { game: smo, end: segv }),
    // Every abort stops in pthread_kill, whatever it was for: each game's apart, beside its sessions.
    sessionOf(3, { end: abort }),
    sessionOf(4, { game: smo, end: abort }),
    sessionOf(5, { game: smo, end: abort }),
    sessionOf(6, { game: smo }),
  ]).endings;
  assert.deepEqual(crashes.map((crash) => [crash.where, crash.signal, crash.pc, crash.game, crash.count, crash.iphones, crash.of]), [
    ["code", 11, "main+0x8903c8", null, 2, 2, null],
    ["system", 6, "__pthread_kill+0x8", smo, 2, 2, 4],
    ["system", 6, "__pthread_kill+0x8", "0400C3F00006E000", 1, 1, 2],
  ]);
  assert.deepEqual(crashes[0].games, ["0400C3F00006E000", smo]);
});

test("a game's verdict follows the game sheets' rules, each iPhone counting once", () => {
  const status = (sessions) => {
    const { verdict } = build(sessions).games[0];
    return [verdict.status, verdict.reasons.map((reason) => reason.key)];
  };
  const good = (n, fields = {}) => sessionOf(n, { fps: { median: 59.5, low5: 50 }, reader: 2, ...fields });
  assert.deepEqual(status([good(1), good(2), good(3)]), ["playable", []]);
  // One iPhone that played five slow sessions weighs as much as each of the two others.
  const slow = Array.from({ length: 5 }, () => good(1, { fps: { median: 20, low5: 15 } }));
  assert.deepEqual(status([...slow, good(2), good(3)]), ["playable", []]);
  const verdict = build([...slow, good(2), good(3)]).games[0].verdict;
  assert.deepEqual([verdict.iphones, verdict.sessions, verdict.fps, verdict.low], [3, 7, 59.5, 50]);
  // Below 90 % of the rate the game asks for, or its slowest 5 % below 75 %.
  assert.deepEqual(status([good(1, { fps: { median: 50, low5: 48 } }), good(2, { fps: { median: 52, low5: 48 } })]), ["issues", ["fps"]]);
  assert.deepEqual(status([good(1, { fps: { median: 59, low5: 40 } }), good(2, { fps: { median: 59, low5: 42 } })]), ["issues", ["slowest"]]);
  // One session in ten that ends badly; half of them.
  const crashed = (n) => good(n, { end: { kind: "crash", signal: 11, pc: "main+0x10", lr: "main+0x0" } });
  assert.deepEqual(status([crashed(1), ...Array.from({ length: 9 }, (_, index) => good(2 + index))]), ["issues", ["bad"]]);
  assert.deepEqual(status([crashed(1), crashed(2), good(3), good(4)]), ["boots", ["bad"]]);
  // No frame at all.
  const blank = (n) => sessionOf(n, { fps: undefined, frames: 0, end: { kind: "boot-failed" } });
  assert.deepEqual(status([blank(1), blank(2)]), ["none", ["noFrame"]]);
  assert.equal(M.verdict([]), null);
});

test("the games of each verdict, and those measured on three iPhones at least, as the game sheets ask", () => {
  const good = (n, fields = {}) => sessionOf(n, { fps: { median: 59.5, low5: 50 }, reader: 2, ...fields });
  const model = build([good(1), good(2), good(3), good(1, { game: "0400486024DEC000" }), sessionOf(4, { game: "0100000000010000", fps: undefined, frames: 0 })]);
  assert.deepEqual(model.gameStatuses, [
    { status: "playable", games: 2, measured: 1 },
    { status: "issues", games: 0, measured: 0 },
    { status: "boots", games: 0, measured: 0 },
    { status: "none", games: 1, measured: 0 },
  ]);
});

test("the players' journey: a step reached counts those before it, even unsaid", () => {
  const journey = build([
    // 1 opened Cartouche, no more; 2 opened it, and the Apple sign-in failed.
    eventOf(1, "app.opened", { setUp: false, signedIn: false }),
    eventOf(2, "app.opened", { setUp: false, signedIn: false }),
    eventOf(2, "error", { origin: "signIn", cause: "appleServer", stage: "account" }),
    // 3 went all the way, and played on two days.
    eventOf(3, "app.opened", { setUp: true, signedIn: true }),
    eventOf(3, "account.signedIn", { seconds: 12 }),
    eventOf(3, "game.installed", { version: "1.0.0" }, { game: "0400C3F00006E000" }),
    onDay("2026-11-09", sessionOf(3)),
    sessionOf(3),
    // 4 ran a version that said neither its sign-in nor its set-up, and played.
    eventOf(4, "game.installed", {}, { game: "0400C3F00006E000" }),
    sessionOf(4),
    // 5 was installed with the player's own certificate, by the Cartouche
    // Installer; 6 too, signed by a signing app on the iPhone.
    eventOf(5, "app.opened", { setUp: false, signedIn: false, signing: "imported" }),
    eventOf(6, "app.opened", { setUp: false, signedIn: false, signing: "iphone", iml: "leftOut", gameKeychains: "leftOut" }),
  ]).journey;
  assert.equal(journey.copies, 6);
  assert.deepEqual(journey.steps.map((step) => [step.key, step.copies]), [["opened", 6], ["signedIn", 4], ["setUp", 2], ["installed", 2], ["played", 2], ["returned", 1]]);
  assert.equal(journey.stuckCopies, 4);
  assert.deepEqual(journey.stuck.map((step) => [step.key, step.copies]), [["opened", 2], ["signedIn", 2], ["setUp", 0], ["installed", 0]]);
  assert.deepEqual(journey.blockers, [{ origin: "signIn", cause: "appleServer", copies: 1 }]);
  assert.equal(journey.neverSignedIn, 1);
});

test("each version says how far its copies got, the newest first", () => {
  const older = { cartouche: "0.11.1" };
  const newer = { cartouche: "0.11.2" };
  const model = build([
    eventOf(1, "app.opened", { setUp: false }, older),
    eventOf(1, "error", { origin: "signIn", cause: "appleServer", error: "SideSign.ServerError 1" }, older),
    eventOf(2, "app.opened", { setUp: true }, older),
    eventOf(2, "account.signedIn", {}, older),
    sessionOf(2, { ...older, end: { kind: "crash", signal: 11, pc: "main+0x10", lr: "main+0x0" } }),
    eventOf(3, "app.opened", { setUp: true }, newer),
    eventOf(3, "account.signedIn", {}, newer),
    sessionOf(3, newer),
  ]);
  assert.deepEqual(model.versions.map((row) => row.version), ["0.11.2", "0.11.1"]);
  const [two, one] = model.versions;
  assert.deepEqual(one.signIn, { ok: 1, failed: 1, copies: 2, okCopies: 1 });
  assert.deepEqual(one.setUp, { share: 0.5, known: 2 });
  assert.deepEqual([one.copies, one.opens, one.players, one.sessions, one.bad, one.errors], [2, 2, 1, 1, 1, 1]);
  assert.deepEqual(one.topError, { origin: "signIn", cause: "appleServer", error: "SideSign.ServerError 1", copies: 1, count: 1 });
  assert.deepEqual([two.copies, two.players, two.bad, two.errors, two.topError], [1, 1, 0, 0, null]);
  // A version picked leaves the others beside it.
  const picked = M.build(answer([eventOf(1, "app.opened", {}, older), eventOf(3, "app.opened", {}, newer)].map(asRow)), CATALOG, { version: "0.11.1" });
  assert.deepEqual(picked.versions.map((row) => row.version), ["0.11.2", "0.11.1"]);
});

test("each game on each model, the most played first", () => {
  const model = build([
    sessionOf(1, { device: "iPhone19,4", reader: 2, fps: { median: 59.9, low5: 55 } }),
    sessionOf(2, { device: "iPhone19,4", reader: 2, fps: { median: 59.5, low5: 55 } }),
    sessionOf(3, { device: "iPhone15,4", fps: undefined, frames: 0, end: { kind: "boot-failed" } }),
    sessionOf(4, { device: "iPhone19,4", game: "0100000000010000", minutes: 5 }),
  ]);
  const { models, games } = model.compatibility;
  assert.deepEqual(models, ["iPhone19,4", "iPhone15,4"]);
  assert.deepEqual(games.map((game) => game.id), ["0400C3F00006E000", "0100000000010000"]);
  assert.deepEqual(games[0].cells.map((cell) => cell && [cell.status, cell.iphones]), [["playable", 2], ["none", 1]]);
  assert.deepEqual(games[1].cells.map((cell) => cell && cell.status), ["playable", null]);
});

test("the settings that change from one session to another come apart from those all share", () => {
  const fluidity = build([
    sessionOf(1, { settings: { DM_OPMODE: "0", DM_RENDER_SCALE: "1.0", DM_LANG: "fr" } }),
    sessionOf(2, { settings: { DM_OPMODE: "1", DM_RENDER_SCALE: "1.0" } }),
  ]).fluidity;
  assert.deepEqual(fluidity.variedSettings.map((item) => [item.key, item.values.length, item.sessions]), [["DM_LANG", 2, 2], ["DM_OPMODE", 2, 2]]);
  assert.deepEqual(fluidity.variedSettings[0].values.find((value) => value.value === null), { value: null, count: 1, installs: null }, "a session without the setting");
  assert.deepEqual(fluidity.sameSettings, ["DM_RENDER_SCALE=1.0"]);
});

test("a measure that only ever says 0, as the GPU's busy time on iOS, says nothing", () => {
  const idle = [sessionOf(1, { gpuBusyMsPerSecond: 0 }), sessionOf(2, { gpuBusyMsPerSecond: 0 })];
  assert.equal(build(idle).heat.gpuBusy, null);
  assert.equal(build([sessionOf(3, { gpuBusyMsPerSecond: 610 }), sessionOf(4, { gpuBusyMsPerSecond: 700 })]).heat.gpuBusy, 655);
});

test("a game counts among the hot ones from half an hour measured", () => {
  assert.equal(M.HOT_MINUTES, 30);
  const heat = build([
    // Twenty minutes of Mario Kart World, all of them hot: too few to tell.
    sessionOf(1, { thermal: { nominal: 0, fair: 0, serious: 20, critical: 0 }, minutes: 20 }),
    // Forty of Super Mario Odyssey, half of them hot.
    sessionOf(2, { game: "0100000000010000", thermal: { nominal: 20, fair: 0, serious: 20, critical: 0 }, minutes: 40 }),
  ]).heat;
  assert.deepEqual(heat.byGame.map((game) => [game.id, game.hotShare, game.minutes, game.iphones]), [["0100000000010000", 0.5, 40, 1]]);
});

test("the page opens on the first day with a report, a week at least, within the window", () => {
  const window = { from: "2026-10-14", today: TODAY };
  assert.deepEqual(M.shownDays(window, [{ day: "2026-11-09" }, { day: TODAY }]), M.dayList("2026-11-04", TODAY));
  assert.deepEqual(M.shownDays(window, [{ day: "2026-10-20" }, { day: TODAY }]), M.dayList("2026-10-20", TODAY));
  assert.deepEqual(M.shownDays(window, []), M.dayList("2026-10-14", TODAY));
  assert.deepEqual(M.shownDays({ from: "2026-11-08", today: TODAY }, [{ day: TODAY }]), M.dayList("2026-11-08", TODAY));
  assert.deepEqual(build([onDay("2026-11-09", eventOf(1, "app.opened", {}))]).days, M.dayList("2026-11-04", TODAY));
});

test("an error only the newest version sent is new; one older versions sent is not", () => {
  const signIn = { origin: "signIn", cause: "appleServer", stage: "account", kind: "invalidResponseFormat", error: "SideSign.ServerError 1" };
  const storage = { origin: "storage", cause: "offline", error: "NSPOSIXErrorDomain 60" };
  const model = build([
    eventOf(1, "error", signIn, { cartouche: "0.11.2" }),
    eventOf(2, "error", signIn, { cartouche: "0.11.2" }),
    eventOf(3, "error", storage, { cartouche: "0.11.1" }),
    eventOf(4, "error", storage, { cartouche: "0.11.2" }),
    eventOf(4, "error", storage, { cartouche: "0.11.2" }),
  ]);
  assert.deepEqual(model.errors.byCode.map((row) => [row.origin, row.newIn, row.iphones, row.count, row.versions]), [
    ["storage", null, 2, 3, ["0.11.2", "0.11.1"]],
    ["signIn", "0.11.2", 2, 2, ["0.11.2"]],
  ]);
  // With one version alone, nothing is new.
  assert.equal(build([eventOf(1, "error", signIn, { cartouche: "0.11.2" })]).errors.byCode[0].newIn, null);
});

test("the errors the newest version still sends come first, those it no longer sends last", () => {
  assert.equal(M.GONE_COPIES, 10);
  const error = (origin) => ({ origin, cause: "network", error: "NSPOSIXErrorDomain 60" });
  const older = { cartouche: "0.11.1" };
  const newer = { cartouche: "0.11.2" };
  const reports = [
    // Both versions sent it, on a copy each.
    eventOf(1, "error", error("storage"), older),
    eventOf(2, "error", error("storage"), newer),
    // The older version alone, on three copies.
    ...[3, 4, 5].map((n) => eventOf(n, "error", error("savesSync"), older)),
    // The newest alone.
    eventOf(6, "error", error("install"), newer),
  ];
  const states = (model) => model.errors.byCode.map((row) => [row.origin, row.state, row.lastIn]);
  // Two copies run the newest version: too few to say it no longer sends an error.
  assert.deepEqual(states(build(reports)), [
    ["storage", "still", "0.11.2"],
    ["install", "new", "0.11.2"],
    ["savesSync", null, "0.11.1"],
  ]);
  // Ten copies run it: the older version's error is gone from it, and goes last.
  const ten = [...reports, ...[7, 8, 9, 10, 11, 12, 13, 14].map((n) => eventOf(n, "app.opened", {}, newer))];
  assert.deepEqual(states(build(ten)), [
    ["storage", "still", "0.11.2"],
    ["install", "new", "0.11.2"],
    ["savesSync", "gone", "0.11.1"],
  ]);
  // With one version alone, none can tell.
  assert.deepEqual(states(build([eventOf(1, "error", error("storage"), newer)])), [["storage", null, "0.11.2"]]);
});

test("what needs a look comes first, the most serious and the widest first", () => {
  const mac = (n, name, fields) => eventOf(100 + n, name, fields, { device: "Mac16,12", ios: "26.6", cartouche: "0.4.2", game: "0100000000010000" });
  const signIn = { origin: "signIn", cause: "appleServer", stage: "account", kind: "invalidResponseFormat", error: "SideSign.ServerError 1" };
  const crash = { kind: "crash", signal: 11, pc: "main+0x8903c8", lr: "main+0x8903bc" };
  const abort = { kind: "crash", signal: 6, pc: "__pthread_kill+0x8", lr: "pthread_kill+0x10c" };
  const model = build([
    // Three copies of the newest version stopped at the Apple sign-in, with an error no version sent before.
    ...[1, 2, 3].flatMap((n) => [eventOf(n, "app.opened", { setUp: false }, { cartouche: "0.11.2" }), eventOf(n, "error", signIn, { cartouche: "0.11.2" })]),
    // A game that drew no frame on two iPhones, in short sessions.
    ...[4, 5].map((n) => sessionOf(n, { game: "0100000000010000", fps: undefined, frames: 0, minutes: 2 })),
    // The same crash in the game's code on two iPhones, three sessions that went well, and one at the edge of its memory.
    ...[6, 7].map((n) => sessionOf(n, { end: crash })),
    sessionOf(8),
    sessionOf(9),
    sessionOf(10, { memory: { ...APP_REPORTS[0].memory, peakMiB: 6000 } }),
    // Another game aborts on two iPhones of five.
    ...[11, 12].map((n) => sessionOf(n, { game: "0400486024DEC000", end: abort })),
    ...[13, 14, 15].map((n) => sessionOf(n, { game: "0400486024DEC000" })),
    // An nxnative commit no Mac could build with.
    mac(1, "builder.failed", { nxnative: "deadbeef00aa", stage: "app build", cause: "app_build" }),
    mac(1, "builder.failed", { nxnative: "deadbeef00aa", stage: "app build", cause: "app_build" }),
    mac(2, "builder.failed", { nxnative: "deadbeef00aa", stage: "app build", cause: "app_build" }),
    mac(2, "builder.built", { nxnative: "0123456789ab", seconds: 1800 }),
  ]);
  assert.deepEqual(model.attention.map((item) => [item.key, item.tone, item.copies]), [
    ["signIn", "critical", 3],
    ["game", "critical", 2],
    ["build", "serious", 2],
    ["crash", "serious", 2],
    ["abort", "serious", 2],
    ["memory", "warning", 5],
    ["newError", "warning", 3],
  ]);
  const byKey = Object.fromEntries(model.attention.map((item) => [item.key, item]));
  assert.deepEqual([byKey.signIn.cause, byKey.signIn.causeCopies, byKey.signIn.section], ["appleServer", 3, "parcours"]);
  assert.deepEqual([byKey.game.game, byKey.game.status], ["0100000000010000", "none"]);
  // Its game on each of the two Macs, though the first tried twice.
  assert.deepEqual([byKey.build.commit, byKey.build.failed, byKey.build.regressions, byKey.build.stage], ["deadbeef00aa", 2, 0, "app build"]);
  assert.deepEqual([byKey.crash.signal, byKey.crash.pc, byKey.crash.count], [11, "main+0x8903c8", 2]);
  // An abort's address is the system's, whatever the game aborted for: it is the game's, with its sessions.
  assert.deepEqual([byKey.abort.game, byKey.abort.signal, byKey.abort.count, byKey.abort.sessions], ["0400486024DEC000", 6, 2, 5]);
  assert.deepEqual([byKey.memory.game, byKey.memory.peak, byKey.memory.limit], ["0400C3F00006E000", 6000, 6143]);
  assert.deepEqual([byKey.newError.version, byKey.newError.origin, byKey.newError.stage, byKey.newError.count], ["0.11.2", "signIn", "account", 3]);
  assert.equal(model.attentionMore, 0);
  // Below the thresholds, nothing.
  assert.deepEqual(build([eventOf(1, "app.opened", {}), sessionOf(1), sessionOf(2)]).attention, []);
});

test("hours without a counted frame may be a log that does not count them, and a game's aborts are said once", () => {
  assert.equal(M.UNCOUNTED_MINUTES, 30);
  const smo = "0100000000010000";
  const blank = (n, minutes) => sessionOf(n, { game: smo, fps: undefined, frames: 0, minutes });
  const pick = (model) => model.attention.map((item) => [item.key, item.tone, item.game, item.uncounted ?? null, item.cause ?? null]);
  // An hour on each of two iPhones without a frame counted: the verdict stays the game sheets', the point says why it may be.
  const uncounted = build([blank(1, 60), blank(2, 60)]);
  assert.equal(uncounted.games[0].verdict.status, "none");
  assert.deepEqual(pick(uncounted), [["game", "serious", smo, true, null]]);
  assert.equal(uncounted.attention[0].minutes, 120);
  assert.deepEqual(pick(build([blank(1, 5), blank(2, 5)])), [["game", "critical", smo, false, null]]);
  // A game that does not hold is not said again for its aborts; another game's, once, by its widest.
  const abort = { kind: "crash", signal: 6, pc: "__pthread_kill+0x8", lr: "pthread_kill+0x10c" };
  const model = build([
    ...[1, 2].map((n) => sessionOf(n, { game: smo, end: abort })),
    ...[3, 4].map((n) => sessionOf(n, { end: { ...abort, cause: "gpuLost" } })),
    ...[5, 6].map((n) => sessionOf(n, { end: abort })),
    ...[7, 8, 9, 10, 11, 12, 13, 14].map((n) => sessionOf(n)),
  ]);
  assert.deepEqual(pick(model), [["game", "serious", smo, false, null], ["abort", "serious", "0400C3F00006E000", null, "gpuLost"]]);
  // Past eight points, the others wait for the page to ask.
  const many = build([
    eventOf(50, "app.opened", {}, { cartouche: "0.11.1" }),
    ...Array.from({ length: 9 }, (_, index) => [1, 2].map((n) => eventOf(n, "error", { origin: "storage", cause: "network", error: "NSPOSIXErrorDomain " + (50 + index) }, { cartouche: "0.11.2" }))).flat(),
  ]);
  assert.deepEqual([many.attention.length, many.attentionMore, many.attentionRest.map((item) => item.key)], [8, 1, ["newError"]]);
});

test("a commit counts each game of each Mac once, as its last try ended, and the games that built before apart", () => {
  const mac = (n, name, game, fields) => eventOf(200 + n, name, fields, { device: "Mac16,7", ios: "27.2.1", cartouche: "0.6.1", game });
  const [smo, botw, pokopia, oot, splatoon] = ["0100000000010000", "01007EF00011E000", "0400A3A01EE4C000", "0400486024DEC000", "0400380020056000"];
  const split = { stage: "shader split", cause: "nxnative", reasons: "named" };
  const model = build([
    // Two Macs built their game with the commit before…
    mac(1, "builder.built", smo, { nxnative: "aaaaaaaaaaaa" }),
    mac(2, "builder.built", botw, { nxnative: "aaaaaaaaaaaa" }),
    // …which no longer builds with the next one.
    mac(1, "builder.failed", smo, { nxnative: "bbbbbbbbbbbb", ...split }),
    mac(2, "builder.failed", botw, { nxnative: "bbbbbbbbbbbb", ...split }),
    // A third Mac builds a game with it, and tries five times a game it never built, whose files stop the build.
    mac(3, "builder.built", oot, { nxnative: "bbbbbbbbbbbb" }),
    ...[1, 2, 3, 4, 5].map(() => mac(3, "builder.failed", pokopia, { nxnative: "bbbbbbbbbbbb", stage: "check v655360 files", cause: "nxnative", reasons: "forced,new" })),
    // A fourth tries four times, with a later commit, a game it never built: nothing builds with that commit, on one Mac.
    ...[1, 2, 3, 4].map(() => mac(4, "builder.failed", splatoon, { nxnative: "cccccccccccc", stage: "check v65536 files", cause: "crashed", reasons: "forced,new" })),
  ]);
  const commits = Object.fromEntries(model.builder.byCommit.map((row) => [row.commit, row]));
  const pick = (row) => [row.built, row.failed, row.tries, row.regressions, row.regressedMacs, row.macs, row.failedMacs, row.stage];
  assert.deepEqual(pick(commits.bbbbbbbbbbbb), [1, 3, 7, 2, 2, 3, 3, "shader split"]);
  assert.deepEqual(pick(commits.cccccccccccc), [0, 1, 4, 0, 0, 1, 1, "check v65536 files"]);
  assert.deepEqual(pick(commits.aaaaaaaaaaaa), [2, 0, 0, 0, 0, 2, 0, null]);
  // What needs a look: the commit that broke two Macs' games, not the Mac that tries again and again.
  assert.deepEqual(model.attention.filter((item) => item.key === "build").map((item) => [item.commit, item.copies, item.regressions, item.failed, item.stage]), [
    ["bbbbbbbbbbbb", 2, 2, 3, "shader split"],
  ]);
  // The failures: each try, of a game on each of four Macs.
  assert.deepEqual([model.builder.failed.count, model.builder.failed.macGames, model.builder.failed.macs], [11, 4, 4]);
  // A game that builds again after a failure with the same commit counts as built.
  const again = build([
    mac(5, "builder.failed", smo, { nxnative: "dddddddddddd", stage: "check v0 files", cause: "nxnative", reasons: "new" }),
    mac(5, "builder.built", smo, { nxnative: "dddddddddddd", reasons: "forced,new" }),
  ]);
  assert.deepEqual(pick(again.builder.byCommit[0]), [1, 0, 1, 0, 0, 1, 0, null]);
});

test("the renewals say what renewed each signature, those Cartouche made itself, and the copies a failure left stuck", () => {
  const failed = { origin: "renewal", error: "SideStore 1", cause: "device", stage: "ResignApp", kind: "noDevice", background: true };
  const model = build([
    eventOf(1, "app.opened", { signatureDays: 6 }),
    eventOf(1, "renewal.done", { seconds: 30, automatic: true, vpnOpened: true }),
    eventOf(1, "signature.renewed", { daysLeft: 7, via: "cartouche" }),
    // Failed, then reinstalled: renewed since.
    eventOf(2, "signature.renewed", { daysLeft: 7, via: "update" }),
    eventOf(2, "error", { ...failed, cause: "offline", stage: "PreflightChecks", background: false }),
    eventOf(2, "signature.renewed", { daysLeft: 7, via: "reinstall" }),
    // Renewed, then failed last, this week: stuck, as the two after it.
    eventOf(3, "renewal.done", { seconds: 50, automatic: false }),
    eventOf(3, "error", failed),
    eventOf(3, "app.opened", { signatureDays: 1 }),
    eventOf(4, "error", failed),
    eventOf(5, "error", failed),
    // A failure older than a signature lasts, the copy silent since: gone, not stuck.
    onDay("2026-10-20", eventOf(6, "error", failed)),
    // Before a renewal said what made it.
    eventOf(7, "signature.renewed", { daysLeft: 7 }),
  ]);
  const r = model.renewals;
  assert.deepEqual([r.renewed, r.renewedCopies], [4, 3]);
  assert.deepEqual(Object.fromEntries(r.via.map((row) => [row.key, row.count])), { cartouche: 1, update: 1, reinstall: 1, unsaid: 1 });
  assert.deepEqual([r.done, r.tried, r.through, r.failed, r.failedCopies], [2, 6, 2, 5, 5]);
  assert.deepEqual([r.automatic.yes, r.automatic.known, r.seconds], [1, 2, 40]);
  assert.deepEqual(r.why.map((row) => [row.stage, row.cause, row.count]), [["ResignApp", "device", 4], ["PreflightChecks", "offline", 1]]);
  assert.deepEqual([r.stuck, r.stuckCause.key, r.low], [3, "device", 1]);
  const [renewal] = model.attention;
  assert.deepEqual([renewal.key, renewal.copies, renewal.cause, renewal.causeCopies, renewal.section], ["renewal", 3, "device", 3, "renouvellements"]);
  assert.deepEqual([model.totals.renewals.copies, model.totals.renewals.through], [6, 2]);
  // Two copies stuck are not yet a point to look at.
  assert.deepEqual(build([eventOf(1, "error", failed), eventOf(2, "error", failed)]).attention, []);
});

test("where the games and the saves are kept, the games folders, and the saves synced on the iPhones and the Macs", () => {
  const mac = { device: "Mac16,12", ios: "26.6", cartouche: "0.7.1" };
  const model = build([
    eventOf(1, "app.opened", { storage: "smb", saves: "smb", gamesFolders: 2, tailscale: true }),
    eventOf(2, "app.opened", { storage: "mac", saves: "smb", gamesFolders: 1, tailscale: false }),
    // Before the folders were said.
    eventOf(3, "app.opened", { storage: "sftp", saves: "none" }),
    eventOf(4, "app.opened", { storage: "smb", saves: "drive", gamesFolders: 4 }),
    eventOf(1, "saves.synced", { step: "send", when: "after", during: 4, duringFailed: 1 }),
    eventOf(2, "saves.synced", { step: "fetch", when: "before" }),
    eventOf(101, "builder.saves", { step: "send", when: "during", place: "share" }, mac),
    eventOf(101, "builder.saves", { step: "same", when: "round", place: "share" }, mac),
    eventOf(1, "error", { origin: "storage", cause: "network", stage: "connect", background: true }),
    eventOf(2, "error", { origin: "saves", cause: "network", stage: "savesSync" }),
  ]);
  const st = model.storage;
  assert.deepEqual(st.games.map((row) => [row.key, row.count]), [["smb", 2], ["mac", 1], ["sftp", 1]]);
  assert.deepEqual(st.savesKind.map((row) => [row.key, row.count]), [["smb", 2], ["drive", 1], ["none", 1]]);
  assert.deepEqual([st.folders.map((row) => [row.key, row.count]), st.foldersKnown], [[["1", 1], ["2", 1], ["3+", 1]], 3]);
  assert.deepEqual([st.tailscale.yes, st.tailscale.known], [1, 2]);
  assert.deepEqual([st.errors.count, st.errors.copies, st.errors.background.share], [1, 1, 1]);
  const sv = st.saves;
  assert.deepEqual([sv.count, sv.iphones, sv.macs, sv.during, sv.duringFailed, sv.errors, sv.errorCopies], [4, 2, 1, 5, 1, 1, 1]);
  assert.deepEqual(Object.fromEntries(sv.steps.map((row) => [row.key, row.count])), { send: 2, fetch: 1, same: 1 });
  assert.deepEqual(Object.fromEntries(sv.moments.map((row) => [row.key, row.count])), { after: 1, before: 1, during: 1, round: 1 });
  // The Mac's saves are not an iPhone's.
  assert.equal(model.totals.iphones, 4);
});

test("each game installed says where it came from, and how its Mac was reached", () => {
  const game = { game: "0100000000010000" };
  const model = build([
    eventOf(1, "game.installed", { version: "1.0.0", from: "mac", link: "cable" }, game),
    eventOf(2, "game.installed", { from: "mac", link: "network" }, game),
    eventOf(3, "game.installed", { from: "cloud" }, game),
    eventOf(4, "game.installed", { from: "smb", folder: "other" }, game),
    // Before 0.15.0, whether it came from the games folder, or nothing.
    eventOf(5, "game.installed", { fromStorage: true }, game),
    eventOf(6, "game.installed", { fromStorage: false }, game),
    eventOf(7, "game.installed", {}, game),
    eventOf(3, "app.opened", { cloud: true }),
    eventOf(8, "app.opened", { cloud: false }),
    eventOf(3, "error", { origin: "install", from: "cloud", cause: "network", stage: "download" }),
    eventOf(4, "error", { origin: "install", from: "smb", cause: "network", stage: "download" }),
  ]);
  assert.equal(model.installs.count, 7);
  assert.deepEqual(Object.fromEntries(model.installs.from.map((row) => [row.key, row.count])), { mac: 2, cloud: 1, smb: 1, storage: 1, file: 1 });
  assert.equal(model.installs.fromKnown, 6);
  assert.deepEqual(model.installs.link.map((row) => [row.key, row.count]), [["cable", 1], ["network", 1]]);
  assert.deepEqual([model.installs.otherFolder.yes, model.installs.otherFolder.known], [1, 1]);
  const iphone = model.cloud.iphone;
  assert.deepEqual([iphone.installs, iphone.copies, iphone.linked.yes, iphone.linked.known, iphone.failed], [1, 1, 1, 2, 1]);
  assert.deepEqual(iphone.byCause.map((row) => [row.key, row.count]), [["network", 1]]);
});

test("Cartouche Cloud's builds, why they failed and what its page refused, apart from the iPhones and the Macs", () => {
  const platform = { device: "CartoucheCloud1,1", ios: "0", cartouche: "1.0", memoryLimitMiB: undefined, increasedMemoryLimit: undefined };
  const cloud = (name, fields, game) => eventOf(900, name, fields, { ...platform, game });
  const odyssey = "0100000000010000";
  const kart = "0400C3F00006E000";
  const model = build([
    eventOf(1, "app.opened", {}),
    cloud("cloud.built", { minutes: 40, gigabytes: 6.5, nxnative: "6c3aeb3d70a1" }, odyssey),
    cloud("cloud.built", { minutes: 60, gigabytes: 8.5, nxnative: "6c3aeb3d70a1" }, kart),
    cloud("cloud.failed", { step: "build", stage: "shaders", cause: "tables", nxnative: "8d62601f0000" }, odyssey),
    cloud("cloud.failed", { step: "build", stage: "shaders", cause: "tables", nxnative: "8d62601f0000" }, kart),
    cloud("cloud.failed", { step: "fetch" }, kart),
    cloud("cloud.refused", { code: "unopened", kind: "packages" }),
    cloud("cloud.refused", { code: "unopened", kind: "packages" }),
    cloud("cloud.refused", { code: "heavy", kind: "zip" }),
  ]);
  const c = model.cloud;
  assert.deepEqual([c.events, c.built, c.failed, c.minutes, c.gigabytes], [8, 2, 3, 50, 7.5]);
  assert.deepEqual(c.why.map((row) => [row.step, row.stage, row.cause, row.count, row.games, row.commit]), [
    ["build", "shaders", "tables", 2, 2, "8d62601f0000"],
    ["fetch", null, null, 1, 1, null],
  ]);
  assert.deepEqual(c.games.map((row) => [row.id, row.built, row.failed]), [[kart, 1, 2], [odyssey, 1, 1]]);
  assert.deepEqual([c.refused.map((row) => [row.key, row.count]), c.refusedKinds.map((row) => [row.key, row.count]), c.refusedCount], [[["unopened", 2], ["heavy", 1]], [["packages", 2], ["zip", 1]], 3]);
  assert.deepEqual([model.totals.cloud.built, model.totals.cloud.failed, model.totals.cloud.share], [2, 3, 0.4]);
  // The same failure twice is a point to look at; once is not.
  assert.deepEqual(model.attention.map((item) => [item.key, item.copies, item.step, item.cause, item.commit]), [["cloud", 2, "build", "tables", "8d62601f0000"]]);
  // The platform is no iPhone, no Mac, and no version of Cartouche.
  assert.equal(model.totals.iphones, 1);
  assert.equal(model.builder.events, 0);
  assert.ok(!model.options.versions.some((row) => row.value === "1.0"));
  assert.ok(!model.options.devices.some((row) => row.value === "CartoucheCloud1,1"));
});

test("a Mac's failures say the Builder's step and its cause, and the console's errors theirs", () => {
  const mac = (n, name, fields) => eventOf(100 + n, name, fields, { device: "Mac16,12", ios: "26.6", cartouche: "0.7.1", game: "0100000000010000" });
  const model = build([
    mac(1, "builder.failed", { stage: "shaders", cause: "tables" }),
    mac(2, "builder.failed", { stage: "shaders", cause: "tables" }),
    mac(2, "builder.failed", { cause: "no_space" }),
    mac(1, "error", { origin: "storage", cause: "network", stage: "connect" }),
    mac(2, "error", { origin: "storage", cause: "network", stage: "connect" }),
    mac(2, "error", { origin: "saves", cause: "noSpace" }),
  ]);
  assert.deepEqual(model.builder.failed.whys.map((row) => [row.stage, row.cause, row.count, row.installs]), [["shaders", "tables", 2, 2], ["?", "no_space", 1, 1]]);
  assert.deepEqual(model.builder.console.map((row) => [row.origin, row.cause, row.count]), [["storage", "network", 2], ["saves", "noSpace", 1]]);
  // A Mac's error is not an iPhone's.
  assert.equal(model.errors.count, 0);
});

test("the sample data fills every section, and is the same each time", () => {
  const first = M.demo(28, CATALOG, NOW);
  assert.equal(JSON.stringify(first), JSON.stringify(M.demo(28, CATALOG, NOW)));
  assert.equal(first.demo, true);
  const model = M.build(first, CATALOG);
  assert.equal(model.days.length, 28);
  assert.equal(model.totals.iphones, 16);
  assert.equal(model.builder.macs, 2);
  assert.deepEqual(model.builder.deviceLanguages.map((item) => item.key), ["fr"]);
  assert.ok(model.devices.deviceLanguages.length >= 4, "the iPhones' own languages");
  assert.ok(model.games.length >= 6);
  assert.ok(model.games.some((game) => game.name === "Super Mario Odyssey" && game.cover === "co1mxf"));
  assert.ok(model.games.every((game) => !game.tightest || game.tightest.ratio < 1), "no game past its iPhone's limit");
  for (const [name, value] of Object.entries({
    sessions: model.totals.sessions,
    errors: model.errors.count,
    crashes: model.endings.crashes.length,
    installs: model.installs.count,
    renewals: model.devices.renewals,
    updates: model.devices.updates.length,
    built: model.builder.built.count,
    signedIn: model.errors.signIn.succeeded,
    signInFailures: model.errors.signIn.failed,
    causes: model.errors.byCause.length,
    issues: model.problems.github.issues.length,
    slowest: model.fluidity.low5Measured,
    fold: model.fluidity.fold?.known ?? 0,
    gpuLost: model.endings.gpuLost.count,
    stuck: model.journey.stuckCopies,
    blockers: model.journey.blockers.length,
    versions: model.versions.length,
    models: model.compatibility.models.length,
    attention: model.attention.length,
    commits: model.builder.byCommit.length,
    macSessions: model.macPlay.sessions,
    macGames: model.macGames.length,
    renewed: model.renewals.renewed,
    renewalsDone: model.renewals.done,
    renewalsFailed: model.renewals.failed,
    renewalsStuck: model.renewals.stuck,
    imported: model.renewals.imported.length,
    folders: model.storage.foldersKnown,
    savesSynced: model.storage.saves.count,
    savesDuring: model.storage.saves.during,
    macSaves: model.storage.saves.macs,
    installFrom: model.installs.from.length,
    installLink: model.installs.link.length,
    cloudBuilt: model.cloud.built,
    cloudFailed: model.cloud.why.length,
    cloudRefused: model.cloud.refusedCount,
    cloudInstalls: model.cloud.iphone.installs,
    cloudLinked: model.cloud.iphone.linked?.yes ?? 0,
  })) {
    assert.ok(value > 0, name);
  }
  assert.ok(model.journey.steps.every((step, index) => !index || step.copies <= model.journey.steps[index - 1].copies), "each step holds fewer copies than the one before");
  const year = M.build(M.demo(365, CATALOG, NOW), CATALOG);
  assert.equal(year.days.length, 365);
});

test("the days of the window, across months and years", () => {
  assert.deepEqual(M.dayList("2026-12-30", "2027-01-02"), ["2026-12-30", "2026-12-31", "2027-01-01", "2027-01-02"]);
  assert.deepEqual(M.dayList("2026-11-10", "2026-11-10"), ["2026-11-10"]);
});

// MARK: The page as a browser runs it

// The page's scripts, but the catalog's JSON. A browser parses a script whole
// before it runs any of it: one error, such as a name declared twice, and
// none of it runs, which left the page without a section from 15 November.
const SCRIPTS = [...PAGE.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/g)]
  .filter(([, attributes]) => !attributes.includes('type="application/json"'))
  .map(([, attributes, source]) => ({ id: /\bid="([^"]+)"/.exec(attributes)?.[1] ?? "?", source }));
const VIEW = SCRIPTS.find((script) => script.id === "view").source;

test("every script of the page compiles", () => {
  assert.deepEqual(SCRIPTS.map((script) => script.id), ["model", "view"]);
  for (const script of SCRIPTS) {
    assert.doesNotThrow(() => new vm.Script(script.source, { filename: `index.html, script ${script.id}` }), script.id);
  }
});

// Just enough of a browser's page for the view (the second script) to draw
// every section, and the charts it draws at the next frame: nothing is laid
// out, and what the view writes is only read back by the tests below.
class StandInNode {
  constructor() {
    this.childNodes = [];
    this.parentNode = null;
  }
  get isConnected() {
    return this.parentNode !== null;
  }
  get textContent() {
    return this.childNodes.map((child) => child.textContent).join("");
  }
  set textContent(value) {
    this.replaceChildren(...(value === null || value === undefined || value === "" ? [] : [String(value)]));
  }
  append(...nodes) {
    for (const node of nodes) {
      const child = node instanceof StandInNode ? node : new StandInText(String(node));
      child.remove();
      child.parentNode = this;
      this.childNodes.push(child);
    }
  }
  replaceChildren(...nodes) {
    for (const child of this.childNodes) child.parentNode = null;
    this.childNodes = [];
    this.append(...nodes);
  }
  remove() {
    if (!this.parentNode) return;
    const siblings = this.parentNode.childNodes;
    siblings.splice(siblings.indexOf(this), 1);
    this.parentNode = null;
  }
  replaceWith(...nodes) {
    const parent = this.parentNode;
    if (!parent) return;
    const rest = parent.childNodes.slice(parent.childNodes.indexOf(this) + 1);
    for (const child of rest) child.remove();
    this.remove();
    parent.append(...nodes, ...rest);
  }
  // Every element below this one, in the page's order.
  *descendants() {
    for (const child of this.childNodes) {
      if (!(child instanceof StandInElement)) continue;
      yield child;
      yield* child.descendants();
    }
  }
}

class StandInText extends StandInNode {
  constructor(text) {
    super();
    this.text = text;
  }
  get textContent() {
    return this.text;
  }
}

class StandInElement extends StandInNode {
  constructor(tag) {
    super();
    this.tagName = tag.toUpperCase();
    this.attributes = new Map();
    this.dataset = {};
    this.hidden = false;
    this.className = "";
    this.listeners = [];
    const classes = new Set();
    this.classList = {
      add: (...names) => names.forEach((name) => classes.add(name)),
      remove: (...names) => names.forEach((name) => classes.delete(name)),
      contains: (name) => classes.has(name),
      toggle: (name, on = !classes.has(name)) => (on ? classes.add(name) : classes.delete(name), on),
    };
    this.style = { setProperty: (name, value) => (this.style[name] = String(value)) };
  }
  get id() {
    return this.getAttribute("id") ?? "";
  }
  get options() {
    return this.childNodes.filter((child) => child.tagName === "OPTION");
  }
  setAttribute(name, value) {
    this.attributes.set(name, String(value));
  }
  getAttribute(name) {
    return this.attributes.get(name) ?? null;
  }
  removeAttribute(name) {
    this.attributes.delete(name);
  }
  addEventListener(type, listener) {
    this.listeners.push({ type, listener });
  }
  getBoundingClientRect() {
    return { x: 0, y: 0, left: 0, top: 0, right: 0, bottom: 0, width: 0, height: 0 };
  }
}

/** The page's model and view run in a stand-in for the browser, on SEARCH
 * (?demo for the sample data) or on what /data answers: the page, its
 * controls, the line under them and what fills main, once the view has
 * read its data and drawn its charts. */
async function runPage({ search = "", answer: body = null, catalog = CATALOG } = {}) {
  const byId = new Map();
  const element = (id, tag = "div") => {
    const found = new StandInElement(tag);
    found.setAttribute("id", id);
    byId.set(id, found);
    return found;
  };
  element("catalog", "script").textContent = JSON.stringify(catalog);
  for (const key of ["game", "device", "version"]) element(`f-${key}`, "select").append(new StandInElement("option"));
  const range = [7, 28, 90, 365].map((days) => Object.assign(new StandInElement("button"), { dataset: { days: String(days) } }));
  const document = {
    documentElement: new StandInElement("html"),
    getElementById: (id) => byId.get(id) ?? element(id),
    querySelectorAll: (selector) => (selector === ".range button" ? range : []),
    createElement: (tag) => new StandInElement(tag),
    createElementNS: (namespace, tag) => new StandInElement(tag),
    createTextNode: (text) => new StandInText(String(text)),
  };
  const frames = [];
  const asked = [];
  const page = vm.createContext({
    document,
    Node: StandInNode,
    URLSearchParams,
    location: { search, hash: "", pathname: "/" },
    history: { replaceState: () => {} },
    innerWidth: 1280,
    addEventListener: () => {},
    scrollTo: () => {},
    requestAnimationFrame: (callback) => frames.push(callback),
    cancelAnimationFrame: () => {},
    fetch: async (url) => {
      asked.push(url);
      return { ok: true, status: 200, json: async () => JSON.parse(JSON.stringify(body)) };
    },
  });
  page.window = page;
  for (const script of SCRIPTS) vm.runInContext(script.source, page, { filename: `index.html, script ${script.id}` });
  // The data read, then the charts drawn at the frames that follow.
  await new Promise((resolve) => setImmediate(resolve));
  while (frames.length) frames.shift()();
  const main = document.getElementById("main");
  return {
    asked,
    state: document.getElementById("state").textContent,
    problem: document.getElementById("problem"),
    sections: main.childNodes.filter((child) => child.tagName === "SECTION").map((section) => section.id),
    main,
  };
}

// The sections the page's menu jumps to.
const JUMPS = [.../<nav class="jump"[\s\S]*?<\/nav>/.exec(PAGE)[0].matchAll(/href="#([a-z]+)"/g)].map(([, id]) => id);

test("the page draws every section of the sample data, and its charts", async () => {
  const page = await runPage({ search: "?demo" });
  assert.equal(page.problem.hidden, true, page.problem.textContent);
  assert.match(page.state, /^À jour à /);
  assert.deepEqual(page.asked, [], "the sample data asks the server nothing");
  assert.ok(JUMPS.length >= 16);
  for (const id of JUMPS) assert.ok(page.sections.includes(id), `the section ${id}`);
  const svgs = [...page.main.descendants()].filter((node) => node.tagName === "SVG");
  assert.ok(svgs.length > 0, "the charts drawn");
  // A lost GPU, in the crashes' table and among what needs a look.
  const text = page.main.textContent;
  assert.match(text, /Perte du GPU/);
  assert.match(text, /Super Mario Odyssey : perte du GPU/);
});

test("the page draws the reports Cartouche makes, as /data sends them", async () => {
  const page = await runPage({ answer: answer(APP_REPORTS.map(asRow).reverse()) });
  assert.equal(page.problem.hidden, true, page.problem.textContent);
  assert.match(page.state, /^À jour à /);
  assert.deepEqual(page.asked, ["/data?days=28"]);
  for (const id of JUMPS) assert.ok(page.sections.includes(id), `the section ${id}`);
  assert.match(page.main.textContent, /Mario Kart World/);
  assert.match(page.main.textContent, /Perte du GPU/);
});

test("a long table shows its first lines, and the others when asked", async () => {
  const games = Array.from({ length: 25 }, (_, index) => "01000000000" + String(index).padStart(2, "0") + "000");
  const page = await runPage({ answer: answer(games.map((game, index) => asRow(sessionOf(index + 1, { game })))) });
  const section = page.main.childNodes.find((child) => child.id === "jeux");
  const rows = () => [...section.descendants()].filter((node) => node.tagName === "TBODY").flatMap((body) => body.childNodes.filter((row) => row.tagName === "TR"));
  assert.equal(rows().length, 20);
  const more = [...section.descendants()].find((node) => node.tagName === "BUTTON" && node.textContent === "Voir les 5 autres jeux");
  assert.ok(more, section.textContent);
  const click = (button) => button.listeners.filter((item) => item.type === "click").forEach((item) => item.listener({ preventDefault() {} }));
  click(more);
  assert.equal(rows().length, 25);
  assert.equal(more.textContent, "Réduire");
  click(more);
  assert.equal(rows().length, 20);
});

test("past eight points to look at, the page shows the others when asked", async () => {
  const page = await runPage({
    answer: answer([
      eventOf(50, "app.opened", {}, { cartouche: "0.11.1" }),
      ...Array.from({ length: 9 }, (_, index) => [1, 2].map((n) => eventOf(n, "error", { origin: "storage", cause: "network", error: "NSPOSIXErrorDomain " + (50 + index) }, { cartouche: "0.11.2" }))).flat(),
    ].map(asRow)),
  });
  const points = () => [...page.main.descendants()].filter((node) => node.tagName === "OL" && node.className === "attention").flatMap((list) => list.childNodes.filter((item) => item.tagName === "LI"));
  assert.equal(points().length, 8);
  const more = [...page.main.descendants()].find((node) => node.tagName === "BUTTON" && node.textContent === "Voir l'autre point, moins répandu");
  assert.ok(more, "the button for the ninth");
  more.listeners.filter((item) => item.type === "click").forEach((item) => item.listener());
  assert.equal(points().length, 9);
});

test("a page that cannot read its data says so, and draws nothing", async () => {
  const page = await runPage({ answer: { schema: 1 } });
  assert.equal(page.problem.hidden, false);
  assert.notEqual(page.problem.textContent, "");
  assert.deepEqual(page.sections, []);
});

// MARK: From the app to the page

// With Node's own SQLite, when it has one: the reports Cartouche makes go
// through the telemetry server into the database, and come out of the
// dashboard into the page's sums.
let sqlite;
try {
  sqlite = await import("node:sqlite");
} catch {
  sqlite = undefined;
}

function sqliteD1() {
  const db = new sqlite.DatabaseSync(":memory:");
  db.exec(SCHEMA_SQL);
  const run = (sql, args) => {
    const statement = db.prepare(sql);
    if (/^\s*SELECT/i.test(sql) || /\bRETURNING\b/i.test(sql)) {
      const rows = statement.all(...args).map((row) => ({ ...row }));
      return { results: rows, meta: { rows_read: rows.length, size_after: 65536 } };
    }
    statement.run(...args);
    return { results: [], meta: { size_after: 65536 } };
  };
  const bound = (sql, args) => ({
    sql,
    args,
    bind: (...more) => bound(sql, more),
    all: async () => run(sql, args),
    run: async () => run(sql, args),
    first: async (column) => {
      const row = run(sql, args).results[0] ?? null;
      return column ? (row?.[column] ?? null) : row;
    },
  });
  return {
    prepare: (sql) => bound(sql, []),
    async batch(statements) {
      return statements.map((statement) => run(statement.sql, statement.args));
    },
  };
}

test("from the app to the page, through the telemetry server and the dashboard", { skip: !sqlite && "Node has no node:sqlite" }, async () => {
  resetThrottle();
  const DB = sqliteD1();
  const sent = await telemetry.fetch(
    new Request("https://telemetry.example.workers.dev/v1/reports", {
      method: "POST",
      headers: { "content-type": "application/json", "cf-connecting-ip": "203.0.113.7" },
      body: JSON.stringify({ reports: APP_REPORTS }),
    }),
    { DB },
    {},
    NOW,
  );
  assert.deepEqual(await sent.json(), { accepted: 2, refused: 0 });
  const answer = await dashboard.fetch(get("/data"), { DB }, SIGNED_IN, NOW);
  assert.equal(answer.status, 200);
  const body = await answer.json();
  assert.equal(body.count, 2);
  assert.deepEqual(body.received, { today: 2, yesterday: 0, installsToday: 1 });
  assert.deepEqual(body.reports, APP_REPORTS.map(asRow).reverse());
  const model = M.build(body, CATALOG);
  assert.equal(model.games[0].name, "Mario Kart World");
  assert.equal(model.totals.sessions, 1);
  assert.equal(model.installs.count, 1);
});
