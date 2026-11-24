-- Finger soccer physics contract v7 (owner request 2026-11-20): goal posts and the inside of the goal (side nets,
-- back net) rebound exactly like the rails for the ball and every disc. Documentation row only (clients simulate
-- locally); mirrors lib/games/finger_soccer/core/bm_engine.dart (kBmRailE). NOT applied live by the agent.
update public.nx_physics_contracts
set version = 'physics-2026-11-20-fs-v7',
    contract = contract || '{
      "rail_restitution":0.9,"goal_post_restitution":0.9,"goal_net_restitution":0.9,
      "ball_wall_restitution":0.9,"ball_wall_restitution_fast":0.9,"player_wall_restitution":0.9,
      "tangential_loss_rails_posts_nets":0,"goal_settle_damping_after_score":{"back":0.2,"side":0.3}
    }'::jsonb,
    updated_at = now()
where game = 'finger_soccer';
