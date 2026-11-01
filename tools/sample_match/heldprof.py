import sys,warnings,numpy as np
warnings.filterwarnings('ignore')
from scipy.io import wavfile
D=sys.argv[1];off=int(sys.argv[2])
sr,x=wavfile.read(D+'/stem_0.wav');m=x.astype(np.float64).mean(1)/32768
db=lambda v:20*np.log10(np.maximum(v,1e-9));nf=lambda n:440*2**((n-69)/12)
N=1<<19;F=np.fft.rfftfreq(N,1/sr)
def H(t0,t1,f0,nh=16):
    seg=m[int(t0*sr):int(t1*sr)];w=np.hanning(len(seg));S=np.abs(np.fft.rfft(seg*w,N))*2/w.sum()
    # sum energy within +-60 cents to include detuned voices
    return db(np.array([np.sqrt(np.sum(S[(F>k*f0*0.966)&(F<k*f0*1.035)]**2)) if k*f0<20000 else 1e-9 for k in range(1,nh+1)]))
print('held notes: harmonic dB (absolute), windows early 0.02-0.15 / late 0.6-0.95')
for t,n in [(33,96),(35,84),(37,72),(39,60),(41,48)]:
    f0=nf(n+off)
    for a,b,lab in [(0.02,0.15,'early'),(0.6,0.95,'late ')]:
        print('%3d %5.0fHz %s'%(n,f0,lab),' '.join('%4.0f'%v for v in H(t+a,t+b,f0)))
