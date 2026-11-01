"""python check.py <export dir> <transpose> render.wav [render.wav ...]: harmonic loss over every note of a full
render (each note up to the next one), by scene, with the level matched once for the whole file."""
import sys;sys.path.insert(0,__file__.rsplit('/',1)[0])
from fitlib import *
x,notes=load_export(sys.argv[1]);TR=float(sys.argv[2])
evs=[n for n in notes if n['len']>=0.2]
slots=[];ts=sorted(set(n['t'] for n in notes))
for e in evs:
    nxt=min([t for t in ts if t>e['t']+1e-3]+[96.3]);slots.append((e['t'],e['t'],min(e['len']+0.9,nxt-e['t']-0.005),e))
HA=hfeats(x,slots,False,TR)
for p in sys.argv[3:]:
    from scipy.io import wavfile
    _,y=wavfile.read(p);y=y.astype(np.float64)/32768;HB=hfeats(y,slots,True,TR);tot,off=hloss(HA,HB)
    sc=[hloss([HA[i] for i,s in enumerate(slots) if int(s[0]//32)==k],[HB[i] for i,s in enumerate(slots) if int(s[0]//32)==k])[0] for k in range(3)]
    per=sorted([(hloss([HA[i]],[HB[i]])[0],s[3]['note'],s[0]) for i,s in enumerate(slots)],reverse=True)[:4]
    print('%-22s all %.1f dB  run %.1f  holds %.1f  velocity %.1f  worst %s'%(p.rsplit('/',1)[-1],tot,*sc,', '.join('%d@%.1fs %.0f'%(n,t,l) for l,n,t in per)))
