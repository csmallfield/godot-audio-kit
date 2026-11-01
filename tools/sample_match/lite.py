"""python lite.py full.json out.json <key> [frames]: a light version of a resynthesis patch, one key zone
(the one nearest <key>) played across the whole keyboard, optionally with fewer frames (every n-th, so the
position curve still lands on them)."""
import sys,json
p=json.load(open(sys.argv[1]));K=int(sys.argv[3]);NF=int(sys.argv[4]) if len(sys.argv)>4 else 0
for o in p['oscillators']:
    t=o.get('table')
    if not isinstance(t,dict) or 'zones' not in t:continue
    z=min(t['zones'],key=lambda z:abs(z['key']-K));fr=z['frames']
    if NF and NF<len(fr):
        st=(len(fr)-1)/(NF-1);fr=[fr[round(i*st)] for i in range(NF)]
    t['zones']=[{'key':z['key'],'frames':fr}]
json.dump(p,open(sys.argv[2],'w'));print('%s: zone %d, %d frames, %d kB'%(sys.argv[2].rsplit('/',1)[-1],z['key'],len(fr),len(json.dumps(p))//1024))
