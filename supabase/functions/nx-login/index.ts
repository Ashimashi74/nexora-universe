// nx-login: sign in with a USERNAME + password without exposing anyone's e-mail to the client.
// POST { username, password } -> GoTrue session JSON (same shape as /auth/v1/token?grant_type=password).
// Internal accounts (<username>@users.nexora.invalid, password prefixed "nx#") are tried first,
// then the e-mail account whose profile has that username. Errors are the GoTrue ones (invalid_credentials, ...).
const URL_ = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });

async function grant(email: string, password: string) {
  const r = await fetch(`${URL_}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: ANON, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  return { status: r.status, body: await r.json().catch(() => ({})) };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error_code: "method_not_allowed" }, 405);
  let username = "", password = "";
  try {
    const b = await req.json();
    username = String(b.username ?? "").trim().toLowerCase();
    password = String(b.password ?? "");
  } catch { /* fallthrough */ }
  if (!/^[a-z0-9_.]{2,24}$/.test(username) || password.length < 6 || password.length > 128) {
    return json({ error_code: "invalid_credentials", msg: "Invalid login credentials" }, 400);
  }
  // 1) internal username account
  let r = await grant(`${username}@users.nexora.invalid`, "nx#" + password);
  if (r.status === 200) return json(r.body);
  if (r.status === 429) return json(r.body, 429);
  // 2) e-mail account owning that username
  const q = await fetch(`${URL_}/rest/v1/rpc/nx_login_email`, {
    method: "POST",
    headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}`, "Content-Type": "application/json" },
    body: JSON.stringify({ p_username: username }),
  });
  const email = q.ok ? await q.json() : null;
  if (typeof email === "string" && email && !email.endsWith("@users.nexora.invalid")) {
    r = await grant(email, password);
    return json(r.body, r.status);
  }
  return json({ error_code: "invalid_credentials", msg: "Invalid login credentials" }, 400);
});
