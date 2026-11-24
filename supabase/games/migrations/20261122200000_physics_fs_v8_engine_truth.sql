-- Finger soccer physics contract v8 (2026-11-22): the documentation row is brought back in line with the engine that
-- actually ships.
--
-- nx_physics_contracts is an audit record only -- nothing in lib/, supabase/functions/ or tool/ reads it, and clients
-- simulate locally. That is exactly why it must not lie: it is the only place on the server that says which physics the
-- released APK runs. Values below are transcribed from lib/games/finger_soccer/core/bm_engine.dart (constants 21..134,
-- strikeOf at 1044) and only touch keys this row already uses.
--
-- What was wrong after v4/v7:
--   * PF1 45 / PF2 3.5 were the 2026-11-20 struck-disc law. The engine was re-fitted afterwards: the constant friction
--     part was dropped entirely and the drag moved to 3.25/s pure speed drag (see the bm_engine.dart comment at 54..62).
--   * launch_scale 2.04 measured ~4.74 world/s, about 4% too hard at full power; kBmLaunch is 1.97.
--   * post_restitution 1.9 is the v1 value for the goal posts and contradicts goal_post_restitution 0.9, which the owner
--     asked for in v7 (posts and nets rebound exactly like the rails). It is removed rather than left to argue with 0.9.
--   * sim_rate, light_disc_mass, spin_radius, the disc spin constants, ball curve, max_aim_error, goal mouth/depth
--     scale, goal hold and reset glide, and the world scale K were implemented in the engine but never recorded here.
--   * Keys left over from the v1/v2 prototype that the current engine does not implement at all are kept (they are
--     owner-authored history) but listed under legacy_keys_not_in_engine so nobody reads them as live tuning.
update public.nx_physics_contracts
set version = 'physics-2026-11-22-fs-v8',
    contract = (contract - 'post_restitution') || '{
      "PF1": 0, "PF2": 3.25,
      "disc_friction_law": "struck discs: pure speed drag, no constant part, no launch glide (v8 re-fit; was PF1 45 / PF2 3.5)",
      "launch_scale": 1.97,
      "launch_scale_history": "1.87 (v3) -> 2.04 (v4, lighter friction) -> 1.97 (v8: 2.04 measured ~4% too hard)",
      "launch_glide_seconds": 0,

      "K": 1.27,
      "sim_rate": 0.85,
      "light_disc_mass": 5.5,
      "spin_radius": 28.8,
      "disc_spin_k": 0.16,
      "disc_spin_max": 22,
      "ball_curve": 0,
      "max_aim_error": 0.11,
      "goal_mouth_scale": 0.965,
      "goal_depth_extra": 0.02,
      "goal_hold_seconds": 2.0,
      "reset_glide_seconds": 1.0,
      "disc_wall_restitution_legacy": 0.48,

      "legacy_keys_not_in_engine": [
        "scene_speed", "shot_power_coefficient", "ball_traction", "fast_ball_drop",
        "field_width_scale", "field_length_scale", "ball_spin_transfer", "goal_half_width", "formation"
      ],
      "legacy_note": "listed keys describe the v1/v2 JS prototype; bm_engine.dart does not implement them. Kept as history.",

      "source": "bm_engine.dart constants 21..134 + strikeOf; 3 reference recordings 480x800 15fps, speeds normalised by each side''s reference power"
    }'::jsonb,
    updated_at = now()
where game = 'finger_soccer';
