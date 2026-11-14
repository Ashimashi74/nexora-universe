import json,subprocess,sys
G='/workspace/tools/godot'
def grab(o,tag): return json.loads([l for l in o.splitlines() if l.startswith(tag)][0][len(tag):])
def run(field,frames,sq):
    o=subprocess.run(['node','nx8_harness.js',str(field),str(frames)]+(['sqrt'] if sq else []),capture_output=True,text=True).stdout
    g=subprocess.run([G,'--headless','--path','/workspace/work/nexgodot','-s','res://tests/parity/nx8_scenario.gd','--',str(field),str(frames)],capture_output=True,text=True,timeout=115).stdout
    return grab(o,'GEO:'),grab(o,'JSON:'),grab(g,'GEO:'),grab(g,'JSON:')
for spec in sys.argv[1:]:
    field,frames,mode=spec.split(':')
    js_geo,js,gd_geo,gd=run(int(field),int(frames),mode=='sqrt')
    geo_ok = js_geo['F']==gd_geo['F'] and js_geo['DEPTH']==gd_geo['DEPTH'] and abs(js_geo['GG']['h']-gd_geo['GG']['h'])<1e-9
    per=[max(abs(x-y) for x,y in zip(a[:-3],b[:-3])) if len(a)==len(b) else float('inf') for a,b in zip(js,gd)]
    first=next((i+1 for i,m in enumerate(per) if m>0.01),None)
    print(f"field {field} frames {frames} math={mode}: geometry equal={geo_ok}  samples {len(per)}s  max dev {max(per):.3e}  first >0.01 at t={first}s  final score/shots js={js[-1][-3:]} gd={gd[-1][-3:]}")
    print('  per-second max dev:',' '.join(f'{x:.1e}' for x in per))
