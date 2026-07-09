// Shared OAuth helpers for the Claude Code token.
// Reverse-engineered from `claude setup-token` (public OAuth 2.0 + PKCE client).
// No secrets live here: client_id is a public identifier.

import {
  readFileSync,
  writeFileSync,
  existsSync,
  openSync,
  closeSync,
  unlinkSync,
  statSync,
} from "node:fs";
import { createHash, randomBytes } from "node:crypto";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

export const CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"; // Claude Code public client
export const AUTHORIZE_URL = "https://claude.com/cai/oauth/authorize";
export const TOKEN_URL = "https://platform.claude.com/v1/oauth/token";
export const REDIRECT_URI = "https://platform.claude.com/oauth/code/callback";
export const SCOPE = "user:inference";

const HERE = dirname(fileURLToPath(import.meta.url));

// Long-lived refresh_token store (gitignored).
export const STORE_PATH = process.env.OAUTH_TOKEN_STORE || join(HERE, ".tokens.json");
// The .env file whose CLAUDE_CODE_OAUTH_TOKEN we keep fresh (repo root by default).
export const ENV_PATH = process.env.OAUTH_ENV_PATH || join(HERE, "..", "..", ".env");
export const ENV_KEY = process.env.OAUTH_ENV_KEY || "CLAUDE_CODE_OAUTH_TOKEN";

const b64url = (buf) =>
  Buffer.from(buf).toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export function makePkce() {
  const verifier = b64url(randomBytes(32));
  const challenge = b64url(createHash("sha256").update(verifier).digest());
  const state = b64url(randomBytes(32));
  return { verifier, challenge, state };
}

export function authorizeUrl({ challenge, state }) {
  const p = new URLSearchParams({
    code: "true",
    client_id: CLIENT_ID,
    response_type: "code",
    redirect_uri: REDIRECT_URI,
    scope: SCOPE,
    code_challenge: challenge,
    code_challenge_method: "S256",
    state,
  });
  return `${AUTHORIZE_URL}?${p}`;
}

async function postToken(body) {
  const res = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    /* handled below */
  }
  if (res.status !== 200 || !json) {
    throw new Error(`token endpoint ${res.status}: ${text.slice(0, 300)}`);
  }
  return json;
}

export function exchangeCode({ code, verifier, state }) {
  return postToken({
    grant_type: "authorization_code",
    code,
    state,
    client_id: CLIENT_ID,
    redirect_uri: REDIRECT_URI,
    code_verifier: verifier,
  });
}

export function refreshTokens(refresh_token) {
  return postToken({ grant_type: "refresh_token", refresh_token, client_id: CLIENT_ID });
}

export function loadStore() {
  if (!existsSync(STORE_PATH)) return null;
  return JSON.parse(readFileSync(STORE_PATH, "utf8"));
}

export function saveStore(tokens) {
  const now = Math.floor(Date.now() / 1000);
  const rec = {
    access_token: tokens.access_token,
    refresh_token: tokens.refresh_token,
    scope: tokens.scope,
    token_uuid: tokens.token_uuid,
    account: tokens.account,
    organization: tokens.organization,
    obtained_at: now,
    access_expires_at: now + (tokens.expires_in ?? 0),
    refresh_expires_at: now + (tokens.refresh_token_expires_in ?? 0),
  };
  writeFileSync(STORE_PATH, JSON.stringify(rec, null, 2) + "\n", { mode: 0o600 });
  return rec;
}

export function updateEnv(access_token) {
  const line = `${ENV_KEY}=${access_token}`;
  let env = existsSync(ENV_PATH) ? readFileSync(ENV_PATH, "utf8") : "";
  const re = new RegExp(`^${ENV_KEY}=.*$`, "m");
  env = re.test(env) ? env.replace(re, line) : env.replace(/\n*$/, "\n") + line + "\n";
  writeFileSync(ENV_PATH, env);
}

// Cross-process lock so concurrent agents don't rotate the refresh_token at once
// (a lost race would break the chain). Steals a lock older than staleMs.
async function withLock(lockPath, fn, { retries = 60, waitMs = 200, staleMs = 30000 } = {}) {
  let fd;
  for (let i = 0; i < retries; i++) {
    try {
      fd = openSync(lockPath, "wx");
      break;
    } catch (e) {
      if (e.code !== "EEXIST") throw e;
      try {
        if (Date.now() - statSync(lockPath).mtimeMs > staleMs) unlinkSync(lockPath);
      } catch {
        /* lock vanished; retry */
      }
      await sleep(waitMs);
    }
  }
  if (fd === undefined) throw new Error(`could not acquire lock ${lockPath}`);
  try {
    return await fn();
  } finally {
    try {
      closeSync(fd);
    } catch {}
    try {
      unlinkSync(lockPath);
    } catch {}
  }
}

// Return a valid access_token, refreshing only if the stored one is within
// skewSec of expiry. Safe under concurrency: the refresh is serialized and
// re-checked after acquiring the lock.
export async function ensureFreshAccessToken({ skewSec = 300 } = {}) {
  const now = () => Math.floor(Date.now() / 1000);
  const fresh = (s) => s?.access_token && s.access_expires_at && s.access_expires_at - now() > skewSec;
  let store = loadStore();
  if (!store?.refresh_token) throw new Error(`no refresh_token in ${STORE_PATH}; run the browser login`);
  if (fresh(store)) return store.access_token;
  return withLock(STORE_PATH + ".lock", async () => {
    store = loadStore(); // another process may have refreshed while we waited
    if (fresh(store)) return store.access_token;
    const tokens = await refreshTokens(store.refresh_token);
    saveStore(tokens);
    return tokens.access_token;
  });
}

export const mask = (t) => (t ? `${t.slice(0, 14)}…${t.slice(-4)} (len ${t.length})` : "(none)");
export const days = (secs) => (secs ? (secs / 86400).toFixed(1) : "?");
