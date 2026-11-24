// The telemetry server's former address (decision 158).
//
// The server started in Ad's own Cloudflare account, at
// https://cartouche-telemetry.<that account's subdomain>.workers.dev, which
// every Cartouche given out before the move has in its Info.plist and sends
// its reports to. The server now lives in the account of the zone
// cartouche.cloud, at TARGET (https://telemetry.cartouche.cloud), and this
// Worker takes the former one's place in the former account, by the same
// name, so that the former address keeps answering: it passes each request
// on to TARGET as it came, and gives back TARGET's answer. It holds nothing,
// keeps no log, and has no database.
//
// While the database moves (telemetry/move.sh), HOLD is "yes": every request
// but GET / gets 503 with a Retry-After, which the apps take as a server
// away for a while; they keep their reports and send them again later
// (launcher/Sources/CartoucheTelemetry.swift), so that nothing reaches the
// former database once its copy has begun, and nothing is lost.

/** Seconds the apps wait before sending again while the database moves. */
export const HOLD_SECONDS = 900;

function holding() {
  return new Response(JSON.stringify({ error: "moving" }), {
    status: 503,
    headers: { "content-type": "application/json", "cache-control": "no-store", "retry-after": String(HOLD_SECONDS) },
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const asksTheName = request.method === "GET" && url.pathname === "/";
    if (env.HOLD === "yes" && !asksTheName) return holding();
    const target = new URL(url.pathname + url.search, env.TARGET);
    const headers = new Headers();
    for (const name of ["content-type", "accept", "user-agent"]) {
      const value = request.headers.get(name);
      if (value !== null) headers.set(name, value);
    }
    const init = { method: request.method, headers, redirect: "manual" };
    if (request.method !== "GET" && request.method !== "HEAD") init.body = await request.arrayBuffer();
    const answer = await fetch(target, init);
    return new Response(answer.body, { status: answer.status, headers: answer.headers });
  },
};
