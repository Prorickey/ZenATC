/**
 * ZenATC HLS signing Worker
 *
 * Validates HMAC-SHA256 signed URLs before forwarding to the origin/cache.
 * Strips ?expires=&signature= before fetching so all users share one cached
 * copy of each .ts segment despite arriving with different signed playlist URLs.
 *
 * Signature algorithm (must match backend/cdn.go computeHMACToken):
 *   message   = "<pathname>:<expires>"
 *   signature = hex( HMAC-SHA256(base64decode(CLOUDFLARE_URL_SIGNING_SECRET), message) )
 *
 * Query params:
 *   expires   — Unix timestamp (seconds); request rejected if in the past
 *   signature — hex-encoded HMAC-SHA256 of "<pathname>:<expires>"
 */

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // Only gate /hls/* paths; pass everything else through unchanged.
    if (!url.pathname.startsWith("/hls/")) {
      return fetch(request);
    }

    // .ts segments are immutable and publicly cacheable — no signature needed.
    // Only playlists (.m3u8) require a valid signed URL.
    if (url.pathname.endsWith(".ts")) {
      return fetch(request, { cf: { cacheEverything: true } });
    }

    // ── Validate query params ─────────────────────────────────────────────────

    const expiresStr = url.searchParams.get("expires");
    const signature = url.searchParams.get("signature");

    if (!expiresStr || !signature) {
      return new Response("Missing signature parameters", { status: 403 });
    }

    const expires = parseInt(expiresStr, 10);
    if (isNaN(expires) || Date.now() / 1000 > expires) {
      return new Response("URL expired", { status: 403 });
    }

    // ── Import signing key ────────────────────────────────────────────────────
    // CLOUDFLARE_URL_SIGNING_SECRET is the same base64-encoded value that the
    // Go backend reads from the environment — base64.StdEncoding.DecodeString.

    let keyBytes;
    try {
      keyBytes = base64Decode(env.CLOUDFLARE_URL_SIGNING_SECRET);
    } catch {
      return new Response("Worker misconfigured", { status: 500 });
    }

    const cryptoKey = await crypto.subtle.importKey(
      "raw",
      keyBytes,
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"]
    );

    // ── Compute expected signature ────────────────────────────────────────────

    const message = `${url.pathname}:${expires}`;
    const sigBytes = await crypto.subtle.sign(
      "HMAC",
      cryptoKey,
      new TextEncoder().encode(message)
    );
    const expected = toHex(new Uint8Array(sigBytes));

    if (!timingSafeEqual(expected, signature.toLowerCase())) {
      return new Response("Invalid signature", { status: 403 });
    }

    // ── Forward to origin / CDN cache (clean URL, no query params) ───────────

    const cleanURL = new URL(url);
    cleanURL.search = "";
    return fetch(cleanURL.toString(), {
      headers: request.headers,
      cf: { cacheEverything: true },
    });
  },
};

// ── Helpers ───────────────────────────────────────────────────────────────────

function base64Decode(b64) {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

function toHex(bytes) {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// Constant-time string comparison to prevent timing attacks.
function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
