import json,subprocess,sys
G='/workspace/tools/godot'
def run(field,frames,feel=False):
    ts=json.loads(subprocess.run(['node','--experimental-strip-types','--no-warnings','scenario.ts',str(field),str(frames)],capture_output=True,text=True).stdout)
    args=[G,'--headless','--path','/workspace/work/nexgodot','-s','res://tests/parity/scenario.gd','--',str(field),str(frames)]+(['feel'] if feel else [])
    o=subprocess.run(args,capture_output=True,text=True,timeout=110).stdout
    gd=json.loads([l for l in o.splitlines() if l.startswith('JSON:')][0][5:])
    return ts,gd
for field,frames in [(int(a.split(':')[0]),int(a.split(':')[1])) for a in sys.argv[1:]]:
    ts,gd=run(field,frames)
    first=None; mx=0; per=[]
    for i,(a,b) in enumerate(zip(ts,gd)):
        m=max(abs(x-y) for x,y in zip(a[:-3],b[:-3]))
        per.append(m); mx=max(mx,m)
        if first is None and m>0.01: first=(i+1)
    print(f"field {field} frames {frames}: seconds sampled {len(per)}  max dev {mx:.3e}  first >0.01 at t={first}s  score ts={ts[-1][-3:]} gd={gd[-1][-3:]}")
    print('  per-second max dev:', ' '.join(f'{x:.1e}' for x in per[:60]))
