-- Finger soccer physics contract v4 (calibration v2 on three reference recordings, 2026-11-20). Documentation row only
-- (clients simulate locally); mirrors lib/games/finger_soccer/core/bm_engine.dart. NOT applied live by the agent.
update public.nx_physics_contracts
set version = 'physics-2026-11-20-ref-v4',
    contract = contract || '{
      "PR":53,"BR":25,"PF1":45,"PF2":3.5,"launch_glide_seconds":0,"launch_scale":2.04,"disc_vmax":4400,
      "ball_hits_disc_impulse":1.0,"struck_disc_impulse":1.0,"pcap_only_when_disc_strikes":true,
      "reference_powers":{"Japan":2,"Starbucks":15,"Paris Saint-Germain":10,"Adidas":10,"Australia":5,"Kakero":10},
      "source":"3 reference recordings 480x800 15fps; speeds normalised by each side''s reference power"
    }'::jsonb,
    updated_at = now()
where game = 'finger_soccer';
