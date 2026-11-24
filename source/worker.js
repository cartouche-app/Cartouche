// Cartouche's source for the player's own SideStore, at
// https://source.cartouche.cloud/ (README.md, docs/decisions/155.md).
//
// The source itself is app/sidestore-player-source.json, which the Showcase
// site workflow publishes on GitHub Pages as https://cartouche.cloud/
// sidestore.json, again each time it changes on main. This Worker gives the
// address a player types into SideStore, and answers with that file as Pages
// has it, kept a few minutes in Cloudflare's cache: nothing to deploy when
// the source changes, and nothing else served.

export const SOURCE = "https://cartouche.cloud/sidestore.json";
export const HOST = "source.cartouche.cloud";
// How long Cloudflare and SideStore may keep the source, in seconds: a new
// version reaches SideStore within minutes of the site's publication.
export const CACHE_SECONDS = 300;
// The addresses that give the source: the bare host, which a player types,
// and the file's own name.
export const PATHS = new Set(["/", "/sidestore.json"]);

const TEXT = { "Content-Type": "text/plain; charset=utf-8", "X-Content-Type-Options": "nosniff" };

function text(status, body, headers = {}) {
  return new Response(body, { status, headers: { ...TEXT, ...headers } });
}

/** Whether TEXT reads as a source SideStore takes: an object, with a list of apps. */
export function isSource(body) {
  try {
    const value = JSON.parse(body);
    return value !== null && typeof value === "object" && !Array.isArray(value) && Array.isArray(value.apps);
  } catch {
    return false;
  }
}

/** The answer to REQUEST, with FETCHER in place of the runtime's fetch in the tests. */
export async function handle(request, fetcher = fetch) {
  const url = new URL(request.url);
  if (request.method !== "GET" && request.method !== "HEAD") {
    return text(405, "Only GET and HEAD.\n", { Allow: "GET, HEAD" });
  }
  if (!PATHS.has(url.pathname)) {
    return text(404, `Cartouche's source for SideStore is at https://${HOST}/\n`);
  }
  let upstream;
  try {
    upstream = await fetcher(SOURCE, { cf: { cacheTtl: CACHE_SECONDS, cacheEverything: true } });
  } catch {
    upstream = null;
  }
  const body = upstream && upstream.ok ? await upstream.text() : null;
  if (body === null || !isSource(body)) {
    // Never a page of GitHub's, or half a file, in SideStore's place.
    return text(502, "The source cannot be read right now: try again in a few minutes.\n", { "Cache-Control": "no-store" });
  }
  return new Response(request.method === "HEAD" ? null : body, {
    status: 200,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": `public, max-age=${CACHE_SECONDS}`,
      "Access-Control-Allow-Origin": "*",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

export default {
  fetch(request) {
    return handle(request);
  },
};
