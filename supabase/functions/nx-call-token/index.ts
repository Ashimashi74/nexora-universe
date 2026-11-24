// NEXORA hub · nx-call-token — short-lived LiveKit token for an Orbit Network call.
// POST { room: <nx_chats.id>, video?: boolean }  (verify_jwt = true)
// → { url, token, room: 'nxg-call-<chat id>', identity, name, ttl }
// Only authenticated members of that chat (nx_chat_members, read with the caller's own RLS) get a token.
// POST { kind: 'room', room: <nx_rooms.id on the games project> } → voice token for a ROOM's stage
// ('nxg-room-<id>'): members only (nx_room_members on the games project, read with the caller's own token);
// manager and speakers publish audio unless the manager muted them, listeners (spectators) only subscribe.
// POST { kind: 'game', room: <nx_rooms.id> | <nx_matches.id>, match?: true } → voice for an online GAME room / match
// ('nxg-game-<room id>'): seated players / match players only, all may publish.
// Secrets (already on the project): LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET.
// Speed: the gateway already verified the JWT (verify_jwt = true), so its `sub` is known up front and every
// lookup (auth.getUser, membership, chat kind, profile) runs in ONE parallel round instead of 3-4 sequential
// ones. A token is still only issued when auth.getUser() confirms the same user and the membership rules pass.
import { createClient } from "npm:@supabase/supabase-js@2";
import { AccessToken } from "npm:livekit-server-sdk@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const GAMES_URL = Deno.env.get("GAMES_SUPABASE_URL") ?? "https://eyzafhrefnqlwcjpcdyg.supabase.co";
const GAMES_KEY = Deno.env.get("GAMES_SUPABASE_ANON_KEY") ??
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImV5emFmaHJlZm5xbHdjanBjZHlnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQ4OTUzNjcsImV4cCI6MjExMDQ3MTM2N30.YfdEhbEbvbQ738snwc5C47LYx-NYRXywX66dgMEZh-M";

// `sub` of the (gateway-verified) bearer JWT; only used to start the lookups early, never trusted on its own.
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

    const auth = req.headers.get("Authorization") ?? "";
    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: auth } },
      auth: { persistSession: false },
    });
    // Started now, awaited together with the lookups below.
    const userP = sb.auth.getUser().then((r) => r.data?.user ?? null, () => null);

    const body = await req.json().catch(() => ({}));
    const room = String(body.room ?? body.room_id ?? "");

    // Without a decodable sub (should not happen behind verify_jwt) fall back to the old sequential order.
    let uid = jwtSub(auth);
    if (!uid) {
      const u0 = await userP;
      if (!u0) return json({ error: "unauthorized" }, 401);
      uid = u0.id;
    }
    // Same order of answers as before: unauthenticated callers get 401 before any 400.
    const authed = async () => {
      const u = await userP;
      return !!u && u.id === uid;
    };
    if (!UUID.test(room)) return (await authed()) ? json({ error: "room required" }, 400) : json({ error: "unauthorized" }, 401);

    const profileP = sb.from("profiles").select("username, avatar").eq("id", uid).maybeSingle();

    if (body.kind === "game") {
      // Voice inside an online GAME room (lobby + the match it starts): { kind: 'game', room: <nx_rooms.id> } or
      // { kind: 'game', room: <nx_matches.id>, match: true }. Seated players (nx_room_players) or the match's players
      // publish; everyone else is refused. Lobby and match share one LiveKit room ('nxg-game-<room id>').
      const gs = createClient(GAMES_URL, GAMES_KEY, {
        global: { headers: { Authorization: auth } },
        auth: { persistSession: false },
      });
      const memberP = body.match === true
        ? gs.from("nx_matches").select("room_id, players").eq("id", room).maybeSingle()
        : gs.from("nx_room_players").select("seat").eq("room_id", room).eq("user_id", uid).maybeSingle();
      const [ok0, mres, pres] = await Promise.all([authed(), memberP, profileP]);
      if (!ok0) return json({ error: "unauthorized" }, 401);
      let key2 = room;
      let ok = false;
      if (body.match === true) {
        const mt = mres.data as { room_id?: string; players?: unknown } | null;
        if (mt && Array.isArray(mt.players) && mt.players.includes(uid)) {
          ok = true;
          key2 = mt.room_id ?? room;
        }
      } else {
        ok = !!mres.data;
      }
      if (!ok) return json({ error: "not_member" }, 403);
      const gp = pres.data;
      const lk = `nxg-game-${key2}`;
      const gat = new AccessToken(key, secret, {
        identity: uid,
        name: gp?.username ?? "Pilot",
        ttl: "15m",
        metadata: JSON.stringify({ avatar: gp?.avatar ?? null, role: "player" }),
      });
      gat.addGrant({ room: lk, roomJoin: true, canPublish: true, canSubscribe: true, canPublishData: true });
      return json({ url, token: await gat.toJwt(), room: lk, identity: uid, name: gp?.username ?? "Pilot",
        canPublish: true, role: "player", ttl: 900 });
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
        ttl: "15m",
        metadata: JSON.stringify({ avatar: rp?.avatar ?? null, role: rm.role }),
      });
      rat.addGrant({ room: lk, roomJoin: true, canPublish: canPub, canSubscribe: true, canPublishData: true });
      return json({ url, token: await rat.toJwt(), room: lk, identity: uid, name: rp?.username ?? "Pilot",
        canPublish: canPub, role: rm.role, ttl: 900 });
    }

    const [ok0, mres, cres, pres] = await Promise.all([
      authed(),
      sb.from("nx_chat_members").select("role").eq("chat_id", room).eq("user_id", uid).maybeSingle(),
      sb.from("nx_chats").select("kind").eq("id", room).maybeSingle(),
      profileP,
    ]);
    if (!ok0) return json({ error: "unauthorized" }, 401);
    const m = mres.data;
    if (!m) return json({ error: "not_member" }, 403);
    const chat = cres.data;
    const prof = pres.data;

    // Channels: only owner/admins speak; everyone else listens.
    const canPublish = chat?.kind !== "channel" || m.role === "owner" || m.role === "admin";
    const name = prof?.username ?? "Pilot";
    const lkRoom = `nxg-call-${room}`;
    const at = new AccessToken(key, secret, {
      identity: uid,
      name,
      ttl: "15m", // only needed to join; LiveKit keeps the session after that
      metadata: JSON.stringify({ avatar: prof?.avatar ?? null, video: !!body.video }),
    });
    at.addGrant({ room: lkRoom, roomJoin: true, canPublish, canSubscribe: true, canPublishData: true });
    return json({ url, token: await at.toJwt(), room: lkRoom, identity: uid, name, canPublish, ttl: 900 });
  } catch (e) {
    return json({ error: "server", detail: String(e).slice(0, 200) }, 500);
  }
});
