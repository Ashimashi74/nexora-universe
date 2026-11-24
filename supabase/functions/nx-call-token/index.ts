// NEXORA hub · nx-call-token — short-lived LiveKit token for Orbit Network calls, Talk Rooms, and Online Games.
// verify_jwt = false at the Edge Gateway so asymmetric (ES256 / JWKS) user tokens are never rejected before
// reaching Deno; strict authentication is enforced here via sb.auth.getUser() before any token is minted.
import { createClient } from "npm:@supabase/supabase-js@2";
import { AccessToken } from "npm:livekit-server-sdk@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-region",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const GAMES_URL = Deno.env.get("GAMES_SUPABASE_URL") ?? "https://eyzafhrefnqlwcjpcdyg.supabase.co";
const GAMES_KEY = Deno.env.get("GAMES_SUPABASE_ANON_KEY") ??
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImV5emFmaHJlZm5xbHdjanBjZHlnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQ4OTUzNjcsImV4cCI6MjExMDQ3MTM2N30.YfdEhbEbvbQ738snwc5C47LYx-NYRXywX66dgMEZh-M";

function jwtSub(auth: string): string | null {
  try {
    const part = auth.replace(/^Bearer\s+/i, "").split(".")[1];
    if (!part) return null;
    const b64 = part.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(part.length / 4) * 4, "=");
    const sub = JSON.parse(atob(b64)).sub;
    return typeof sub === "string" && UUID.test(sub) ? sub : null;
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method" }, 405);
  try {
    const url = Deno.env.get("LIVEKIT_URL") ?? "wss://nexora-space-xzjzlfyl.livekit.cloud";
    const key = Deno.env.get("LIVEKIT_API_KEY");
    const secret = Deno.env.get("LIVEKIT_API_SECRET");
    if (!key || !secret) return json({ error: "calls_not_configured" }, 503);

    const supaUrl = Deno.env.get("SUPABASE_URL")!;
    const supaAnon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const socialUrl = Deno.env.get("SOCIAL_SUPABASE_URL") ?? supaUrl;
    const socialKey = Deno.env.get("SOCIAL_SUPABASE_ANON_KEY") ?? supaAnon;

    const auth = req.headers.get("Authorization") ?? "";
    if (!auth) return json({ error: "unauthorized" }, 401);

    const sb = createClient(supaUrl, supaAnon, {
      global: { headers: { Authorization: auth } },
      auth: { persistSession: false },
    });
    const userP = sb.auth.getUser().then((r) => r.data?.user ?? null, () => null);

    const body = await req.json().catch(() => ({}));
    const room = String(body.room ?? body.room_id ?? "");

    let uid = jwtSub(auth);
    if (!uid) {
      const u0 = await userP;
      if (!u0) return json({ error: "unauthorized" }, 401);
      uid = u0.id;
    }
    const authed = async () => {
      const u = await userP;
      return !!u && u.id === uid;
    };
    if (!UUID.test(room)) return (await authed()) ? json({ error: "room required" }, 400) : json({ error: "unauthorized" }, 401);

    const profileP = sb.from("profiles").select("username, avatar").eq("id", uid).maybeSingle();

    if (body.kind === "game") {
      const gs = createClient(GAMES_URL, GAMES_KEY, {
        global: { headers: { Authorization: auth } },
        auth: { persistSession: false },
      });
      if (body.match === true) {
        const [ok0, mres, pres] = await Promise.all([
          authed(),
          gs.from("nx_matches").select("room_id, players").eq("id", room).maybeSingle(),
          profileP,
        ]);
        if (!ok0) return json({ error: "unauthorized" }, 401);
        const mt = mres.data as { room_id?: string | null; players?: unknown } | null;
        let ok = !!(mt && Array.isArray(mt.players) && mt.players.includes(uid));
        const key2 = mt?.room_id ?? room;
        if (!ok && mt?.room_id) {
          const rm = await gs.from("nx_room_members").select("role, muted").eq("room_id", mt.room_id).eq("user_id", uid).maybeSingle();
          ok = !!rm.data;
        }
        if (!ok) return json({ error: "not_member" }, 403);
        const gp = pres.data;
        const lk = `nxg-game-${key2}`;
        const gat = new AccessToken(key, secret, {
          identity: uid,
          name: gp?.username ?? "Pilot",
          ttl: "30m",
          metadata: JSON.stringify({ avatar: gp?.avatar ?? null, role: "player" }),
        });
        gat.addGrant({ room: lk, roomJoin: true, canPublish: true, canSubscribe: true, canPublishData: true });
        return json({
          url,
          token: await gat.toJwt(),
          room: lk,
          identity: uid,
          name: gp?.username ?? "Pilot",
          canPublish: true,
          role: "player",
          ttl: 1800,
        });
      }

      const [ok0, rpRes, rgRes, rmRes, pres] = await Promise.all([
        authed(),
        gs.from("nx_room_players").select("seat").eq("room_id", room).eq("user_id", uid).maybeSingle(),
        gs.from("nx_room_game_players").select("seat").eq("room_id", room).eq("user_id", uid).maybeSingle(),
        gs.from("nx_room_members").select("role, muted").eq("room_id", room).eq("user_id", uid).maybeSingle(),
        profileP,
      ]);
      if (!ok0) return json({ error: "unauthorized" }, 401);
      const ok = !!(rpRes.data || rgRes.data || rmRes.data);
      if (!ok) return json({ error: "not_member" }, 403);
      const gp = pres.data;
      const lk = `nxg-game-${room}`;
      const gat = new AccessToken(key, secret, {
        identity: uid,
        name: gp?.username ?? "Pilot",
        ttl: "30m",
        metadata: JSON.stringify({ avatar: gp?.avatar ?? null, role: "player" }),
      });
      gat.addGrant({ room: lk, roomJoin: true, canPublish: true, canSubscribe: true, canPublishData: true });
      return json({
        url,
        token: await gat.toJwt(),
        room: lk,
        identity: uid,
        name: gp?.username ?? "Pilot",
        canPublish: true,
        role: "player",
        ttl: 1800,
      });
    }

    if (body.kind === "room") {
      const gs = createClient(GAMES_URL, GAMES_KEY, {
        global: { headers: { Authorization: auth } },
        auth: { persistSession: false },
      });
      const [ok0, rres, pres] = await Promise.all([
        authed(),
        gs.from("nx_room_members").select("role, muted").eq("room_id", room).eq("user_id", uid).maybeSingle(),
        profileP,
      ]);
      if (!ok0) return json({ error: "unauthorized" }, 401);
      const rm = rres.data;
      if (!rm) return json({ error: "not_member" }, 403);
      const rp = pres.data;
      const canPub = (rm.role === "manager" || rm.role === "speaker") && !rm.muted;
      const lk = `nxg-room-${room}`;
      const rat = new AccessToken(key, secret, {
        identity: uid,
        name: rp?.username ?? "Pilot",
        ttl: "30m",
        metadata: JSON.stringify({ avatar: rp?.avatar ?? null, role: rm.role }),
      });
      rat.addGrant({ room: lk, roomJoin: true, canPublish: canPub, canSubscribe: true, canPublishData: true });
      return json({
        url,
        token: await rat.toJwt(),
        room: lk,
        identity: uid,
        name: rp?.username ?? "Pilot",
        canPublish: canPub,
        role: rm.role,
        ttl: 1800,
      });
    }

    const social = socialUrl === supaUrl
      ? sb
      : createClient(socialUrl, socialKey, {
          global: { headers: { Authorization: auth } },
          auth: { persistSession: false },
        });
    const [ok0, mres, cres, pres] = await Promise.all([
      authed(),
      social.from("nx_chat_members").select("role").eq("chat_id", room).eq("user_id", uid).maybeSingle(),
      social.from("nx_chats").select("kind").eq("id", room).maybeSingle(),
      profileP,
    ]);
    if (!ok0) return json({ error: "unauthorized" }, 401);
    const m = mres.data;
    if (!m) return json({ error: "not_member" }, 403);
    const chat = cres.data;
    const prof = pres.data;

    const canPublish = chat?.kind !== "channel" || m.role === "owner" || m.role === "admin";
    const name = prof?.username ?? "Pilot";
    const lkRoom = `nxg-call-${room}`;
    const at = new AccessToken(key, secret, {
      identity: uid,
      name,
      ttl: "30m",
      metadata: JSON.stringify({ avatar: prof?.avatar ?? null, video: !!body.video }),
    });
    at.addGrant({ room: lkRoom, roomJoin: true, canPublish, canSubscribe: true, canPublishData: true });
    return json({ url, token: await at.toJwt(), room: lkRoom, identity: uid, name, canPublish, ttl: 1800 });
  } catch (e) {
    return json({ error: "server", detail: String(e).slice(0, 200) }, 500);
  }
});
