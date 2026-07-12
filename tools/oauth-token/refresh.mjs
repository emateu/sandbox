#!/usr/bin/env node
// Refresh CLAUDE_CODE_OAUTH_TOKEN from the stored refresh_token. No browser, no
// dependencies. A refresh rotates the refresh_token and resets its ~28d window.
//
//   node refresh.mjs           force a refresh and rewrite .env  (manual / cron)
//   node refresh.mjs --print   print a valid access_token, refreshing only if near
//                              expiry (used by the container's claude() wrapper);
//                              concurrency-safe.

import {
  loadStore,
  saveStore,
  refreshTokens,
  updateEnv,
  ensureFreshAccessToken,
  mask,
  days,
  STORE_PATH,
  ENV_KEY,
} from "./lib.mjs";

if (process.argv.includes("--print")) {
  try {
    process.stdout.write(await ensureFreshAccessToken());
  } catch (e) {
    console.error("oauth-token:", e.message);
    process.exit(1);
  }
} else {
  const store = loadStore();
  if (!store?.refresh_token) {
    console.error(`No refresh_token in ${STORE_PATH}.`);
    console.error(`Run the one-time browser login first:  ./get-token.sh`);
    process.exit(1);
  }
  let tokens, rec;
  try {
    tokens = await refreshTokens(store.refresh_token);
    rec = saveStore(tokens);
  } catch (e) {
    console.error("refresh failed:", e.message);
    console.error("If the refresh_token expired (>28d idle) or was revoked, run: ./get-token.sh");
    process.exit(1);
  }
  // Kept out of the catch above: a missing .env is not a failed refresh, and
  // reporting it as one sends you off chasing an expired token.
  try {
    updateEnv(tokens.access_token);
  } catch (e) {
    console.log(`refreshed ✔  access ${mask(tokens.access_token)}  (valid 8h)`);
    console.error(`\n${e.message}`);
    process.exit(1);
  }
  console.log(`refreshed ✔  access ${mask(tokens.access_token)}  (valid 8h)`);
  console.log(`refresh_token rotated, valid ~${days(rec.refresh_expires_at - rec.obtained_at)}d`);
  console.log(`.env updated: ${ENV_KEY}`);
}
