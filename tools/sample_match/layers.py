"""python layers.py <export dir> <transpose>: look for a second, detuned layer on the held notes: the fine
spectrum around harmonics 1-6 over 0.1-1.0 s, the strongest side peak per harmonic, in cents."""
import sys;sys.path.insert(0,__file__.rsplit('/',1)[0])
from fitlib import *
x,notes=load_export(sys.argv[1]);TR=float(sys.argv[2]);m=x.mean(1)
for n in sorted([n for n in notes if 32<=n['t']<44 and n['len']>=0.9],key=lambda n:n['note']):
    seg=m[int((n['t']+.1)*SR):int((n['t']+1.0)*SR)];N=len(seg);X=np.abs(np.fft.rfft(seg*np.hanning(N),16*N));f=np.fft.rfftfreq(16*N,1/SR)
    f0=440*2**((n['note']+TR-69)/12);row=[]
    for k in range(1,7):
        c=np.linspace(-80,80,321);v=np.interp(k*f0*2**(c/1200),f,X);i0=np.argmax(v);main=c[i0]
        side=v.copy();side[np.abs(c-main)<12]=0;i1=np.argmax(side)
        row.append('h%d main %+.0f side %+.0f (%.0f dB)'%(k,main,c[i1]-main,20*np.log10(side[i1]/v[i0]+1e-9)))
    print(n['note'],' | '.join(row))
