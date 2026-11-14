// Runs the NX8 build's own www/js/game.js (unmodified physics) headless in node and prints a deterministic
// scenario trace (same scenario as nx8_scenario.gd). Usage: node nx8_harness.js <field> <frames> [sqrt]
//  sqrt: replace Math.hypot by sqrt(x²+y²) so both sides use identical arithmetic (isolates porting errors).
const fs = require('fs');
const SRC = '/workspace/work/nx8/UPDATENXG/nexora_work/www/js/game.js';
const field = +(process.argv[2] || 1), frames = +(process.argv[3] || 3000), useSqrt = process.argv.includes('sqrt');
const stub = new Proxy(function () {}, { get: (t, k) => (k === Symbol.toPrimitive ? () => 0 : k === 'then' ? undefined : stub), apply: () => stub, construct: () => stub, set: () => true });
globalThis.window = stub; globalThis.document = stub; globalThis.Audio = stub; globalThis.Image = stub; globalThis.localStorage = stub;
globalThis.innerWidth = 1080; globalThis.innerHeight = 1920; globalThis.devicePixelRatio = 1;
globalThis.requestAnimationFrame = () => 0; globalThis.fetch = () => new Promise(() => {});
if (useSqrt) Math.hypot = (...a) => { let s = 0; for (const v of a) s += v * v; return Math.sqrt(s); };
let src = fs.readFileSync(SRC, 'utf8');
const tail = 'requestAnimationFrame(loop);\n})();';
if (!src.includes(tail)) throw new Error('game.js tail not found');
src = src.replace(tail, `globalThis.__nx={setup(f,forms){SET.fld=f;form=forms.slice();C={mode:'local',names:['',''],mirror:false,ai:-1,aiLvl:1,tt:0,mt:0};SET.lim=99;mleft=0;sd=false;geo();score=[0,0];reset(0);menuOpen=false;inMatch=true;last=0;acc=0},
 loop,fire,LMAX,get bodies(){return bodies},get ball(){return ball},get phase(){return phase},get turn(){return turn},get score(){return score},
 geo(){return{F,GG,DEPTH,CX,KY,f:FIELDS[SET.fld]}}};\n})();`);
new Function(src)();
const N = globalThis.__nx;
N.setup(field, [0, 3]);
const out = [];
let shots = 0;
for (let f = 0; f < frames; f++) {
  if (N.phase === 'aim') {
    let best = null, bd = 1e9; const ball = N.ball;
    for (const b of N.bodies) if (b.team === N.turn && b !== ball) { const d = Math.sqrt((ball.x - b.x) ** 2 + (ball.y - b.y) ** 2); if (d < bd) { bd = d; best = b; } }
    const ang = (shots * 0.37) % 0.5 - 0.25;
    const a = Math.atan2(ball.y - best.y, ball.x - best.x) + ang;
    const l = N.LMAX * (0.55 + (shots % 5) * 0.11);
    N.fire(best, Math.cos(a) * l, Math.sin(a) * l, l); shots++;
  }
  N.loop((f + 1) * 1000 / 60);
  if (f % 60 === 59) out.push(N.bodies.flatMap(b => [b.x, b.y]).concat([N.score[0], N.score[1], shots]));
}
const g = N.geo();
console.log('GEO:' + JSON.stringify({ F: g.F, GG: g.GG, DEPTH: g.DEPTH, KY: g.KY }));
console.log('JSON:' + JSON.stringify(out));
