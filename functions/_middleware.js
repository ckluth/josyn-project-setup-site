// Cloudflare Pages Function — edge-enforced HTTP Basic Auth (shared password).
//
// Runs on Cloudflare's edge BEFORE any static asset in this project is served,
// so nothing is delivered until the correct password is supplied. This is real
// server-side auth (unlike a client-side JS gate).
//
// The password is NOT stored here. Set it as a Pages environment variable:
//   Cloudflare dashboard -> your Pages project -> Settings ->
//   Environment variables -> add `SITE_PASSWORD` (mark as encrypted / secret).
//
// UX: the browser shows a username + password prompt. Any username is accepted;
// only the password is checked — so effectively it is "one shared password".

const REALM = "josyn-project-setup";

// Timing-safe-ish comparison to avoid leaking length/prefix via response time.
function safeEqual(a, b) {
  const enc = new TextEncoder();
  const ab = enc.encode(a);
  const bb = enc.encode(b);
  if (ab.length !== bb.length) return false;
  let diff = 0;
  for (let i = 0; i < ab.length; i++) diff |= ab[i] ^ bb[i];
  return diff === 0;
}

function unauthorized() {
  return new Response("Authentication required.", {
    status: 401,
    headers: {
      "WWW-Authenticate": `Basic realm="${REALM}", charset="UTF-8"`,
      "Cache-Control": "no-store",
    },
  });
}

export async function onRequest(context) {
  const { request, env, next } = context;

  const expected = env.SITE_PASSWORD;
  // Fail closed: if no password is configured, deny everything.
  if (!expected) return unauthorized();

  const header = request.headers.get("Authorization") || "";
  const [scheme, encoded] = header.split(" ");
  if (scheme !== "Basic" || !encoded) return unauthorized();

  let decoded = "";
  try {
    decoded = atob(encoded);
  } catch {
    return unauthorized();
  }

  // decoded is "username:password"; only the password matters.
  const idx = decoded.indexOf(":");
  const password = idx === -1 ? "" : decoded.slice(idx + 1);

  if (!safeEqual(password, expected)) return unauthorized();

  return next();
}
