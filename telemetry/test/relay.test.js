// Tests of the relay at the telemetry server's former address
// (telemetry/relay/worker.js), with a stand-in for fetch.
//
//     node --test telemetry/test/relay.test.js

import assert from "node:assert/strict";
import { afterEach, beforeEach, test } from "node:test";

import relay, { HOLD_SECONDS } from "../relay/worker.js";

const FORMER = "https://cartouche-telemetry.former.workers.dev";
const TARGET = "https://telemetry.cartouche.cloud";
const OPEN = { TARGET };
const HOLDING = { TARGET, HOLD: "yes" };

let asked;
const realFetch = globalThis.fetch;

beforeEach(() => {
  asked = [];
  globalThis.fetch = async (url, init) => {
    asked.push({ url: String(url), ...init, headers: Object.fromEntries(new Headers(init.headers)) });
    if (new URL(url).pathname === "/") return new Response("Cartouche telemetry\n", { headers: { "content-type": "text/plain" } });
    return new Response(JSON.stringify({ accepted: 2, refused: 0 }), {
      status: 200,
      headers: { "content-type": "application/json", "cache-control": "no-store" },
    });
  };
});

afterEach(() => {
  globalThis.fetch = realFetch;
});

const report = (path = "/v1/reports", body = '{"reports":[{},{}]}') =>
  new Request(`${FORMER}${path}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "user-agent": "Cartouche/0.15.1",
      "cf-connecting-ip": "198.51.100.7",
      cookie: "never=passed",
    },
    body,
  });

test("a report sent to the former address reaches the server at its new one, as it came", async () => {
  const body = '{"reports":[{"id":"a"},{"id":"b"}]}';
  const answer = await relay.fetch(report("/v1/reports", body), OPEN);
  assert.equal(answer.status, 200);
  assert.deepEqual(await answer.json(), { accepted: 2, refused: 0 });
  assert.equal(asked.length, 1);
  assert.equal(asked[0].url, `${TARGET}/v1/reports`);
  assert.equal(asked[0].method, "POST");
  assert.equal(new TextDecoder().decode(asked[0].body), body);
  assert.equal(asked[0].redirect, "manual");
  // What the server reads, and nothing else of the iPhone's.
  assert.deepEqual(asked[0].headers, { "content-type": "application/json", "user-agent": "Cartouche/0.15.1" });
});

test("every path the server answers goes on, with its query", async () => {
  for (const path of ["/v1/forget", "/v1/problems", "/v1/games", "/nothing?x=1"]) {
    await relay.fetch(report(path), OPEN);
  }
  assert.deepEqual(asked.map((one) => one.url), [
    `${TARGET}/v1/forget`,
    `${TARGET}/v1/problems`,
    `${TARGET}/v1/games`,
    `${TARGET}/nothing?x=1`,
  ]);
});

test("the server's answer comes back as it is: its status, its headers and its body", async () => {
  globalThis.fetch = async () =>
    new Response('{"error":"slow down"}', { status: 429, headers: { "retry-after": "60", "content-type": "application/json" } });
  const answer = await relay.fetch(report(), OPEN);
  assert.equal(answer.status, 429);
  assert.equal(answer.headers.get("retry-after"), "60");
  assert.deepEqual(await answer.json(), { error: "slow down" });
});

test("the former address still says whose it is, from the server", async () => {
  const answer = await relay.fetch(new Request(`${FORMER}/`), OPEN);
  assert.equal(await answer.text(), "Cartouche telemetry\n");
  assert.equal(asked[0].url, `${TARGET}/`);
  assert.equal(asked[0].body, undefined);
});

test("while the database moves, the apps are asked to send again later, and nothing goes on", async () => {
  for (const path of ["/v1/reports", "/v1/forget", "/v1/problems", "/v1/games"]) {
    const answer = await relay.fetch(report(path), HOLDING);
    assert.equal(answer.status, 503);
    assert.equal(answer.headers.get("retry-after"), String(HOLD_SECONDS));
    assert.equal(answer.headers.get("cache-control"), "no-store");
    assert.deepEqual(await answer.json(), { error: "moving" });
  }
  assert.equal(asked.length, 0);
  // The apps take any answer but 2xx, 400, 413 and 422 as one to send again.
  assert.ok(HOLD_SECONDS >= 300 && HOLD_SECONDS <= 3600);
  // Its name, from the new server, which the move's checks read.
  const name = await relay.fetch(new Request(`${FORMER}/`), HOLDING);
  assert.equal(await name.text(), "Cartouche telemetry\n");
});
