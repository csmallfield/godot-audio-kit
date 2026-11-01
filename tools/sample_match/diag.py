"""python diag.py <export dir> <transpose> <render.wav>: per run note, level difference and the tilt of the
harmonic-level difference (dB per octave of harmonic number), render against original."""
import sys;sys.path.insert(0,__file__.rsplit('/',1)[0])
from fitlib import *
from scipy.io import wavfile
x,notes=load_export(sys.argv[1]);TR=float(sys.argv[2])
evs=[n for n in notes if n['t']<32];slots=[(e['t'],e['t'],0.24,e) for e in evs]
HA=hfeats(x,slots,False,TR);_,y=wavfile.read(sys.argv[3]);HB=hfeats(y.astype(np.float64)/32768,slots,True,TR)
for i,s in enumerate(slots):
    a=10*np.log10(np.mean(10**(HA[i][0]/10),0));b=10*np.log10(np.mean(10**(HB[i][0]/10),0));K=min(len(a),len(b),16)
    a,b=a[:K],b[:K];d=b-a;lv=10*np.log10(np.sum(10**(b/10))/np.sum(10**(a/10)));k=np.log2(np.arange(1,K+1));w=a>a.max()-40
    sl=np.polyfit(k[w],(d-d[0])[w],1)[0] if w.sum()>2 else 0
    if s[3]['note']%3==0:print('%3d level %+5.1f  tilt %+5.1f dB/oct'%(s[3]['note'],lv,sl))
