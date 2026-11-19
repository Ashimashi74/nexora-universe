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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method" }, 405);
  try {
    const url = Deno.env.get("LIVEKIT_URL") ?? "wss://nexora-space-xzjzlfyl.livekit.cloud";
    const key = Deno.env.get("LIVEKIT_API_KEY");
    const secret = Deno.env.get("LIVEKIT_API_SECRET");
    if (!key || !secret) return json({ error: "calls_not_configured" }, 503);

    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });
    const { data: u } = await sb.auth.getUser();
    if (!u?.user) return json({ error: "unauthorized" }, 401);

    const body = await req.json().catch(() => ({}));
    const room = String(body.room ?? body.room_id ?? "");
    if (!UUID.test(room)) return json({ error: "room required" }, 400);

    if (body.kind === "game") {
      // Voice inside an online GAME room (lobby + the match it starts): { kind: 'game', room: <nx_rooms.id> } or
      // { kind: 'game', room: <nx_matches.id>, match: true }. Seated players (nx_room_players) or the match's players
      // publish; everyone else is refused. Lobby and match share one LiveKit room ('nxg-game-<room id>').
      const gUrl = Deno.env.get("GAMES_SUPABASE_URL") ?? "https://eyzafhrefnqlwcjpcdyg.supabase.co";
      const gKey = Deno.env.get("GAMES_SUPABASE_ANON_KEY") ??
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImV5emFmaHJlZm5xbHdjanBjZHlnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQ4OTUzNjcsImV4cCI6MjExMDQ3MTM2N30.YfdEhbEbvbQ738snwc5C47LYx-NYRXywX66dgMEZh-M";
      const gs = createClient(gUrl, gKey, {
        global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
        auth: { persistSession: false },
      });
      let key2 = room;
      let ok = false;
      if (body.match === true) {
        const { data: mt } = await gs.from("nx_matches").select("room_id, players").eq("id", room).maybeSingle();
        if (mt && Array.isArray(mt.players) && mt.players.includes(u.user.id)) {
          ok = true;
          key2 = mt.room_id ?? room;
        }
      } else {
        const { data: rp2 } = await gs.from("nx_room_players").select("seat").eq("room_id", room)
          .eq("user_id", u.user.id).maybeSingle();
        ok = !!rp2;
      }
      if (!ok) return json({ error: "not_member" }, 403);
      const { data: gp } = await sb.from("profiles").select("username, avatar").eq("id", u.user.id).maybeSingle();
      const lk = `nxg-game-${key2}`;
      const gat = new AccessToken(key, secret, {
        identity: u.user.id,
        name: gp?.username ?? "Pilot",
        ttl: "15m",
        metadata: JSON.stringify({ avatar: gp?.avatar ?? null, role: "player" }),
      });
      gat.addGrant({ room: lk, roomJoin: true, canPublish: true, canSubscribe: true, canPublishData: true });
      return json({ url, token: await gat.toJwt(), room: lk, identity: u.user.id, name: gp?.username ?? "Pilot",
        canPublish: true, role: "player", ttl: 900 });
    }

    if (body.kind === "room") {
      const gUrl = Deno.env.get("GAMES_SUPABASE_URL") ?? "https://eyzafhrefnqlwcjpcdyg.supabase.co";
      const gKey = Deno.env.get("GAMES_SUPABASE_ANON_KEY") ??
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImV5emFmaHJlZm5xbHdjanBjZHlnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQ4OTUzNjcsImV4cCI6MjExMDQ3MTM2N30.YfdEhbEbvbQ738snwc5C47LYx-NYRXywX66dgMEZh-M";
      const gs = createClient(gUrl, gKey, {
        global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
        auth: { persistSession: false },
      });
      const { data: rm } = await gs.from("nx_room_members").select("role, muted").eq("room_id", room)
        .eq("user_id", u.user.id).maybeSingle();
      if (!rm) return json({ error: "not_member" }, 403);
      const { data: rp } = await sb.from("profiles").select("username, avatar").eq("id", u.user.id).maybeSingle();
      const canPub = (rm.role === "manager" || rm.role === "speaker") && !rm.muted;
      const lk = `nxg-room-${room}`;
      const rat = new AccessToken(key, secret, {
        identity: u.user.id,
        name: rp?.username ?? "Pilot",
        ttl: "15m",
        metadata: JSON.stringify({ avatar: rp?.avatar ?? null, role: rm.role }),
      });
      rat.addGrant({ room: lk, roomJoin: true, canPublish: canPub, canSubscribe: true, canPublishData: true });
      return json({ url, token: await rat.toJwt(), room: lk, identity: u.user.id, name: rp?.username ?? "Pilot",
        canPublish: canPub, role: rm.role, ttl: 900 });
    }

    const { data: m } = await sb.from("nx_chat_members").select("role").eq("chat_id", room).eq("user_id", u.user.id).maybeSingle();
    if (!m) return json({ error: "not_member" }, 403);
    const { data: chat } = await sb.from("nx_chats").select("kind").eq("id", room).maybeSingle();
    const { data: prof } = await sb.from("profiles").select("username, avatar").eq("id", u.user.id).maybeSingle();

    // Channels: only owner/admins speak; everyone else listens.
    const canPublish = chat?.kind !== "channel" || m.role === "owner" || m.role === "admin";
    const name = prof?.username ?? "Pilot";
    const lkRoom = `nxg-call-${room}`;
    const at = new AccessToken(key, secret, {
      identity: u.user.id,
      name,
      ttl: "15m", // only needed to join; LiveKit keeps the session after that
      metadata: JSON.stringify({ avatar: prof?.avatar ?? null, video: !!body.video }),
    });
    at.addGrant({ room: lkRoom, roomJoin: true, canPublish, canSubscribe: true, canPublishData: true });
    return json({ url, token: await at.toJwt(), room: lkRoom, identity: u.user.id, name, canPublish, ttl: 900 });
  } catch (e) {
    return json({ error: "server", detail: String(e).slice(0, 200) }, 500);
  }
});
