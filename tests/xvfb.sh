#!/bin/bash
# Start a virtual X display :99 for rendered UI screenshots (no root, no apt).
# Downloads xvfb + deps from deb.debian.org (trixie arm64), extracts to /tmp/debs/root,
# and patches the Xvfb binary: "/usr/bin" (xkbcomp dir) -> "/tmp", "/var/lib/xkb/" -> "/tmp/",
# with /tmp/xkbcomp as a wrapper that sets LD_LIBRARY_PATH. Result: /tmp/debs/Xvfb2.
# Usage: tests/xvfb.sh   then   DISPLAY=:99 godot --rendering-driver opengl3 ...
set -e
D=/tmp/debs; R=$D/root
export LD_LIBRARY_PATH=$R/usr/lib/aarch64-linux-gnu:$R/lib/aarch64-linux-gnu
if [ ! -x $D/Xvfb2 ]; then
  mkdir -p $D/d $R; cd $D
  curl -sS https://deb.debian.org/debian/dists/trixie/main/binary-arm64/Packages.gz | gunzip > Packages
  python3 - <<'E'
import re
pk={}
for blk in open('Packages').read().split('\n\n'):
    d={}
    for l in blk.split('\n'):
        if ': ' in l and not l.startswith(' '):
            k,v=l.split(': ',1); d[k]=v
    if 'Package' in d: pk[d['Package']]=d
skip={'libc6','libgcc-s1','debconf','dpkg','perl-base','libstdc++6','base-files'}
need=['xvfb','xauth','x11-xkb-utils','xkb-data']; seen=set(); out=[]
while need:
    p=need.pop()
    if p in seen or p in skip or p not in pk: continue
    seen.add(p); out.append(pk[p]['Filename'])
    for dep in re.split(r',\s*',pk[p].get('Depends','')+','+pk[p].get('Pre-Depends','')):
        n=dep.split('|')[0].strip().split(' ')[0].split(':')[0]
        if n: need.append(n)
open('list','w').write('\n'.join(out))
E
  cat list | xargs -P 12 -I{} sh -c 'curl -sS -o d/$(basename {}) https://deb.debian.org/debian/{}'
  for f in d/*.deb; do dpkg-deb -x $f $R; done
  python3 - <<'E'
b=bytearray(open('/tmp/debs/root/usr/bin/Xvfb','rb').read())
for old,new in [(b'/usr/bin\0',b'/tmp'),(b'/var/lib/xkb/\0',b'/tmp/')]:
    i=b.find(old); assert i>0
    b[i:i+len(old)]=new.ljust(len(old),b'\0')
open('/tmp/debs/Xvfb2','wb').write(b)
E
  chmod +x $D/Xvfb2
fi
printf '#!/bin/sh\nLD_LIBRARY_PATH=%s exec %s/usr/bin/xkbcomp "$@"\n' "$LD_LIBRARY_PATH" $R > /tmp/xkbcomp
chmod +x /tmp/xkbcomp
mkdir -p /tmp/.X11-unix; chmod 1777 /tmp/.X11-unix
if [ ! -S /tmp/.X11-unix/X99 ]; then
  (nohup $D/Xvfb2 :99 -screen 0 1080x2400x24 -xkbdir $R/usr/share/X11/xkb -nolisten tcp +extension GLX > /tmp/xvfb.log 2>&1 &)
  sleep 3
fi
ls /tmp/.X11-unix/X99 && echo "Xvfb :99 up"
