-- Finger soccer physics contract v3: calibrated frame by frame on the owner's reference recording (2026-11-20).
-- Mirrors lib/games/finger_soccer/core/bm_engine.dart (world units, speeds x K = 1.27). Clients simulate locally and
-- exchange shot velocities; this row documents the live tuning for admin tools and future server checks.
update public.nx_physics_contracts
set version = 'physics-2026-11-20-ref-v3',
    contract = contract || '{
      "PR":75,"BR":37.5,"player_mass":8,"ball_mass":2.6,"HV":4,"PCAP":190,"BKICK":1.05,
      "PF1":280,"PF2":5.0,"PV0":181,"disc_stop":30,"launch_glide_seconds":0.22,"launch_glide_friction":0.35,
      "launch_scale":1.87,"LMAX":320,"strike_base":0.39,"strike_per_power":0.116,
      "ball_friction":23,"ball_drag":1.08,"ball_vmax":4000,"disc_vmax":4200,
      "ball_wall_restitution":0.72,"ball_wall_restitution_fast":0.62,"player_wall_restitution":0.48,
      "player_player_restitution":0.22,"ball_player_restitution":0.55,
      "source":"reference recording 480x800 15fps, pitch 325px = 936 world"
    }'::jsonb,
    updated_at = now()
where game = 'finger_soccer';
