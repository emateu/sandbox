#!/usr/bin/env node
// Drives a Chrome over CDP through the claude.ai OAuth login + consent, then
// exchanges the resulting code for tokens. Normally invoked by get-token.sh, which
// launches the Chrome and sets CHROME_CDP.
//
// Real, headed browser required: claude.ai is behind Cloudflare, which blocks
// headless/synthetic browsers.
//
// Requires: npm install (playwright-core)

import { createInterface } from "node:readline/promises";
import { stdin as input, stdout as output } from "node:process";
import { chromium } from "playwright-core";
import { makePkce, authorizeUrl, exchangeCode, saveStore, updateEnv, mask, ENV_KEY } from "./lib.mjs";

const CDP = process.env.CHROME_CDP || "http://127.0.0.1:9223";
const log = (...a) => console.error("·", ...a);

async function ask(q) {
  const rl = createInterface({ input, output });
  const a = (await rl.question(q)).trim();
  rl.close();
  return a;
}

let browser;
try {
  browser = await chromium.connectOverCDP(CDP);
} catch {
  console.error(`Could not reach a Chrome CDP endpoint at ${CDP}.`);
  console.error(`Run ./get-token.sh — it launches Chrome and sets CHROME_CDP.`);
  process.exit(1);
}

const email = process.argv[2] || process.env.OAUTH_EMAIL || (await ask("claude.ai email: "));

// Reuse the default context + its blank tab (get-token.sh already launches a fresh
// profile), so we drive the window that's already open instead of spawning a second.
const ctx = browser.contexts()[0] ?? (await browser.newContext());
const page = ctx.pages()[0] ?? (await ctx.newPage());
const pkce = makePkce();

log("opening authorize page…");
await page.goto(authorizeUrl(pkce), { waitUntil: "domcontentloaded", timeout: 60000 });
await page.waitForTimeout(2000);

// Login page: fill email, continue. Skipped if the session is already logged in.
try {
  const emailField = page.getByPlaceholder(/email/i);
  if (await emailField.count()) {
    await emailField.first().fill(email);
    await page
      .getByRole("button", { name: /continue with email/i })
      .or(page.getByRole("button", { name: /^continue$/i }))
      .first()
      .click();
    log("email submitted — check your inbox for the code");
    await page.waitForTimeout(2500);

    const code = await ask("paste the email code: ");
    const otp = page
      .locator("input[autocomplete='one-time-code']")
      .or(page.getByPlaceholder(/code/i))
      .or(page.locator("input[inputmode='numeric']"));
    await otp.first().fill(code);
    await page
      .getByRole("button", { name: /continue|verify|log ?in|submit/i })
      .first()
      .click()
      .catch(() => {});
    await page.waitForTimeout(2500);
  }
} catch (e) {
  log("login step:", e.message);
}

// Consent screen: click Authorize.
try {
  await page.getByRole("button", { name: /^authorize$/i }).click({ timeout: 20000 });
} catch (e) {
  log("authorize click:", e.message);
}

// Capture the authorization code from the callback redirect.
let cb = null;
const start = Date.now();
while (Date.now() - start < 30000 && !cb) {
  for (const p of ctx.pages()) {
    let u;
    try {
      u = new URL(p.url());
    } catch {
      continue;
    }
    if (u.host === "platform.claude.com" && u.pathname.includes("/oauth/code")) {
      const code = u.searchParams.get("code");
      const state = u.searchParams.get("state");
      if (code) {
        cb = { code, state };
        break;
      }
    }
  }
  if (!cb) await new Promise((r) => setTimeout(r, 500));
}
if (!cb) {
  console.error("Did not capture the callback code. Re-run, or check the browser state.");
  process.exit(1);
}

const tokens = await exchangeCode({ code: cb.code, verifier: pkce.verifier, state: cb.state });
saveStore(tokens);
updateEnv(tokens.access_token);
await ctx.close().catch(() => {});
console.log(`login ✔  access ${mask(tokens.access_token)}  ·  refresh_token stored (~28d)`);
console.log(`.env updated: ${ENV_KEY}`);
process.exit(0);
