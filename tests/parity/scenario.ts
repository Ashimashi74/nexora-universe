// Deterministic parity scenario for the TS engine (run: node --experimental-strip-types scenario.ts <field> <frames>)
import { Engine, LMAX } from './engine.ts';
const field = +(process.argv[2] || 0), frames = +(process.argv[3] || 3000), dt = 1 / 60;
const e = new Engine({ field, ball: 0, forms: [0, 3], ai: false, aiLvl: 1, limit: 99, matchTime: 0, turnTime: 0, vip: [false, false], first: 0 } as any);
const out: number[][] = [];
let shots = 0;
for (let f = 0; f < frames; f++) {
  if (e.phase === 'aim') {
    let best: any = null, bd = 1e9;
    for (const b of e.bodies) if (b.team === e.turn && b !== e.ball) { const d = Math.hypot(e.ball.x - b.x, e.ball.y - b.y); if (d < bd) { bd = d; best = b; } }
    const ang = (shots * 0.37) % 0.5 - 0.25;
    const dx0 = e.ball.x - best.x, dy0 = e.ball.y - best.y, a = Math.atan2(dy0, dx0) + ang;
    const l = LMAX * (0.55 + (shots % 5) * 0.11);
    e.fire(best, Math.cos(a) * l, Math.sin(a) * l, l); shots++;
  }
  e.update(dt); e.events.length = 0;
  if (f % 60 === 59) out.push(e.bodies.flatMap(b => [b.x, b.y]).concat([e.score[0], e.score[1], shots]));
}
console.log(JSON.stringify(out));
