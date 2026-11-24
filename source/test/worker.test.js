// Tests of the source's Worker (source/worker.js), with a stand-in for the
// site that serves the source.
//
//     node --test source/test/worker.test.js

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import worker, { CACHE_SECONDS, HOST, SOURCE, handle, isSource } from "../worker.js";

const FILE = readFileSync(new URL("../../app/sidestore-player-source.json", import.meta.url), "utf-8");

/** A stand-in for GitHub Pages that answers STATUS and BODY, and notes what it was asked. */
function site(status = 200, body = FILE) {
  const asked = [];
  const fetcher = async (url, init) => {
    asked.push({ url, init });
    return new Response(body, { status, headers: { "Content-Type": "application/json" } });
  };
  return { asked, fetcher };
}

const request = (path = "/", method = "GET") => new Request(`https://${HOST}${path}`, { method });

test("the bare address gives the source, as the site publishes it", async () => {
  const { asked, fetcher } = site();
  const answer = await handle(request("/"), fetcher);
  assert.equal(answer.status, 200);
  assert.equal(answer.headers.get("Content-Type"), "application/json; charset=utf-8");
  assert.equal(answer.headers.get("Cache-Control"), `public, max-age=${CACHE_SECONDS}`);
  assert.equal(await answer.text(), FILE);
  assert.deepEqual(asked.map((one) => one.url), ["https://cartouche.cloud/sidestore.json"]);
  // Kept in Cloudflare's cache for a few minutes, so that the site is asked
  // seldom.
  assert.deepEqual(asked[0].init.cf, { cacheTtl: CACHE_SECONDS, cacheEverything: true });
});

test("the file's own name gives it too, and HEAD its headers alone", async () => {
  assert.equal(await (await handle(request("/sidestore.json"), site().fetcher)).text(), FILE);
  const head = await handle(request("/", "HEAD"), site().fetcher);
  assert.equal(head.status, 200);
  assert.equal(head.headers.get("Content-Type"), "application/json; charset=utf-8");
  assert.equal(await head.text(), "");
});

test("nothing else is served, and nothing is asked of the site for it", async () => {
  for (const path of ["/index.html", "/sidestore", "/apps.json", "/../sidestore.json.bak", "/.env"]) {
    const { asked, fetcher } = site();
    const answer = await handle(request(path), fetcher);
    assert.equal(answer.status, 404, path);
    assert.match(await answer.text(), /https:\/\/source\.cartouche\.cloud\//);
    assert.equal(asked.length, 0, path);
  }
  for (const method of ["POST", "PUT", "DELETE"]) {
    const answer = await handle(request("/", method), site().fetcher);
    assert.equal(answer.status, 405, method);
    assert.equal(answer.headers.get("Allow"), "GET, HEAD");
  }
});

test("when the site does not give a source, SideStore gets an error, never the page in its place", async () => {
  const cases = [
    site(404, "<!doctype html><title>404</title>"),
    site(200, "<!doctype html><title>Cartouche</title>"),
    site(200, FILE.slice(0, 40)),
    site(200, "[]"),
    site(503, FILE),
    { fetcher: async () => { throw new TypeError("network"); } },
  ];
  for (const { fetcher } of cases) {
    const answer = await handle(request("/"), fetcher);
    assert.equal(answer.status, 502);
    assert.equal(answer.headers.get("Cache-Control"), "no-store");
    assert.match(answer.headers.get("Content-Type"), /^text\/plain/);
  }
});

test("the source the repository keeps reads as one", () => {
  assert.ok(isSource(FILE));
  assert.ok(!isSource("{}"));
  assert.ok(!isSource("null"));
  assert.equal(SOURCE, "https://cartouche.cloud/sidestore.json");
});

test("the runtime's entry point answers through handle", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = site().fetcher;
  try {
    const answer = await worker.fetch(request("/"));
    assert.equal(await answer.text(), FILE);
  } finally {
    globalThis.fetch = original;
  }
});
