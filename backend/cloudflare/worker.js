/**
 * ZenATC HLS access Worker
 *
 * Gates every /hls/* request (both the .m3u8 playlist and each .ts segment) on a
 * short-lived signed access cookie, then forwards the CLEAN URL with the cookie
 * stripped — so the edge cache key stays URL-only and all users still share one
 * cached copy of each segment.
 *
 * Cookie (set by backend /assert-and-stream, must match backend/cdn.go):
 *   name  = "zenatc_hls"
 *   value = "<expires>.<hexsig>"
 *   sig   = hex( Ed25519-Sign(privateKey, "/hls/:<expires>") )
 *
 * The Worker holds only the PUBLIC key, so it can verify but never mint cookies.
 */

const COOKIE_NAME = "zenatc_hls";
const COOKIE_SCOPE = "/hls/";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // Only gate /hls/* paths; pass everything else through unchanged.
    if (!url.pathname.startsWith("/hls/")) {
      return fetch(request);
    }

    // ── Read and parse the access cookie ──────────────────────────────────────

    const token = getCookie(request, COOKIE_NAME);
    if (!token) {
      return new Response("Missing access cookie", { status: 403 });
    }

    const dot = token.indexOf(".");
    if (dot < 0) {
      return new Response("Malformed access cookie", { status: 403 });
    }
    const expiresStr = token.slice(0, dot);
    const sigHex = token.slice(dot + 1);

    const expires = parseInt(expiresStr, 10);
    if (isNaN(expires) || Date.now() / 1000 > expires) {
      return new Response("Access expired", { status: 403 });
    }

    // ── Import the public verification key ────────────────────────────────────
    // CLOUDFLARE_URL_SIGNING_PUBLIC_KEY is the base64-encoded 32-byte raw Ed25519
    // public key printed by the Go backend at startup. It is not a secret.

    let cryptoKey;
    try {
      const keyBytes = base64Decode(env.CLOUDFLARE_URL_SIGNING_PUBLIC_KEY);
      cryptoKey = await crypto.subtle.importKey(
        "raw",
        keyBytes,
        { name: "Ed25519" },
        false,
        ["verify"]
      );
    } catch {
      return new Response("Worker misconfigured", { status: 500 });
    }

    // ── Verify the signature ──────────────────────────────────────────────────

    let sigBytes;
    try {
      sigBytes = hexDecode(sigHex);
    } catch {
      return new Response("Invalid access cookie", { status: 403 });
    }

    const message = `${COOKIE_SCOPE}:${expires}`;
    const valid = await crypto.subtle.verify(
      { name: "Ed25519" },
      cryptoKey,
      sigBytes,
      new TextEncoder().encode(message)
    );

    if (!valid) {
      return new Response("Invalid access cookie", { status: 403 });
    }

    // ── Forward to origin / CDN cache (strip the cookie so the cache is shared) ─

    const headers = new Headers(request.headers);
    headers.delete("Cookie");
    const cleanURL = new URL(url);
    cleanURL.search = "";
    return fetch(cleanURL.toString(), {
      headers,
      cf: { cacheEverything: true },
    });
  },
};

// ── Helpers ───────────────────────────────────────────────────────────────────

function getCookie(request, name) {
  const header = request.headers.get("Cookie");
  if (!header) return null;
  for (const part of header.split(";")) {
    const eq = part.indexOf("=");
    if (eq < 0) continue;
    if (part.slice(0, eq).trim() === name) {
      return part.slice(eq + 1).trim();
    }
  }
  return null;
}

function base64Decode(b64) {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

function hexDecode(hex) {
  if (hex.length % 2 !== 0) throw new Error("odd-length hex");
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    const byte = parseInt(hex.substr(i * 2, 2), 16);
    if (isNaN(byte)) throw new Error("invalid hex");
    bytes[i] = byte;
  }
  return bytes;
}
