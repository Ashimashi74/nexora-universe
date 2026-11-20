-- Finger soccer contract v4: reference proportions (owner screenshot 2026-11-20): disc 0.12 / ball 0.056 / goal mouth
-- 0.34 of the playing width. Mirrors PR, BR and kBmGoalArtScale in lib/games/finger_soccer/core/bm_engine.dart.
update public.nx_physics_contracts
set version = 'physics-2026-11-20-ref-v4',
    contract = contract || '{"PR":53,"BR":25,"goal_art_scale":0.92,"source_sizes":"reference screenshot, pitch 620px: disc 75px, ball 35px, mouth 213px"}'::jsonb,
    updated_at = now()
where game = 'finger_soccer';
