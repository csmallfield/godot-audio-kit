"""python motion.py <export dir> <transpose> [render.wav ...]: movement inside held notes (std of harmonics
1-12 in dB over 0.3-0.95 s, the beating of detuned voices) and stereo width (left/right correlation)."""
import sys;sys.path.insert(0,__file__.rsplit('/',1)[0])
from fitlib import *
x,notes=load_export(sys.argv[1]);TR=float(sys.argv[2])
holds=sorted([n for n in notes if 32<=n['t']<44 and n['len']>=0.9],key=lambda n:n['note'])
def stats(y):
    mv=[];cr=[]
    for n in holds:
        f0=440*2**((n['note']+TR-69)/12);a,b=int((n['t']+.3)*SR),int((n['t']+.95)*SR);seg=y[a:b].mean(1)
        L=int(max(3*SR/f0,441));fr=np.arange(0,len(seg)-L,220);t=np.arange(L)
        K=int(min(12,15000//f0));H=np.array([[abs(np.dot(seg[i:i+L]*np.hanning(L),np.exp(-2j*np.pi*k*f0*t/SR))) for k in range(1,K+1)] for i in fr])
        d=20*np.log10(H+1e-9);w=H.mean(0)/H.mean(0).max();mv.append(np.sum(d.std(0)*w)/np.sum(w))
        l,r=y[a:b,0],y[a:b,1];cr.append(np.dot(l,r)/np.sqrt(np.dot(l,l)*np.dot(r,r)+1e-20))
    return np.mean(mv),np.mean(cr)
print('%-14s movement %.2f dB  L/R correlation %.2f'%('original',*stats(x)))
from scipy.io import wavfile
for p in sys.argv[3:]:
    _,y=wavfile.read(p);print('%-14s movement %.2f dB  L/R correlation %.2f'%(p.rsplit('/',1)[-1][:14],*stats(y.astype(float)/32768)))
