import sys,warnings,numpy as np
warnings.filterwarnings('ignore')
from scipy.io import wavfile
from scipy.signal import find_peaks
sr,x=wavfile.read(sys.argv[1]+'/stem_0.wav');m=x.astype(np.float64).mean(1)/32768
N=1<<18;F=np.fft.rfftfreq(N,1/sr)
def pk(t0,t1,top=12):
    seg=m[int(t0*sr):int(t1*sr)];S=np.abs(np.fft.rfft(seg*np.hanning(len(seg)),N));d=20*np.log10(S/S.max()+1e-12)
    p,_=find_peaks(d,height=-40,distance=int(8/F[1]));p=p[np.argsort(-d[p])][:top];p=np.sort(p)
    return ' '.join('%.0f(%.0f)'%(F[i],d[i]) for i in p)
for spec in sys.argv[2:]:
    t0,t1,lab=spec.split(':');print(lab,'|',pk(float(t0),float(t1)))
