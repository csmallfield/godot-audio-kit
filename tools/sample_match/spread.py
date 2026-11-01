"""python spread.py <export dir> <transpose> <center key> render.wav [render.wav ...]: harmonic loss per note
of a full render, grouped by distance from <center key> in semitones (the chromatic run and the holds)."""
import sys;sys.path.insert(0,__file__.rsplit('/',1)[0])
from fitlib import *
from scipy.io import wavfile
x,notes=load_export(sys.argv[1]);TR=float(sys.argv[2]);C=int(sys.argv[3])
evs=[n for n in notes if n['len']>=0.2 and n['t']<44];ts=sorted(set(n['t'] for n in notes))
slots=[(e['t'],e['t'],min(e['len']+0.9,min([t for t in ts if t>e['t']+1e-3]+[96.3])-e['t']-0.005),e) for e in evs]
HA=hfeats(x,slots,False,TR);G=[(0,3),(3,7),(7,13),(13,19),(19,25),(25,40)]
print('%-16s all   '%'render'+'  '.join('±%d-%d'%g for g in G))
for p in sys.argv[4:]:
    _,y=wavfile.read(p);HB=hfeats(y.astype(np.float64)/32768,slots,True,TR);tot,off=hloss(HA,HB)
    FL=max(h[0].max() for h in HA)-60
    # Per note at the file's one level, so level errors by key count.
    per=[(abs(s[3]['note']-C),hloss([HA[i]],[HB[i]],off,FL)[0]) for i,s in enumerate(slots)]
    row=['%5.1f'%np.mean([l for d,l in per if g[0]<=d<g[1]]) if any(g[0]<=d<g[1] for d,_ in per) else '   - ' for g in G]
    print('%-16s %4.1f  '%(p.rsplit('/',1)[-1][:16],tot)+'   '.join(row))
