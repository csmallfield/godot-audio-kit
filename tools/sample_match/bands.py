"""Octave-band energy over time: python bands.py <dir> <t0> <dur s> [step ms]"""
import sys,warnings,numpy as np
warnings.filterwarnings('ignore')
from scipy.io import wavfile
from scipy.signal import stft
D,t0,dur=sys.argv[1],float(sys.argv[2]),float(sys.argv[3]);step=float(sys.argv[4]) if len(sys.argv)>4 else 10
sr,x=wavfile.read(D+'/stem_0.wav');m=x.astype(np.float64).mean(1)/32768
seg=m[int(t0*sr):int((t0+dur)*sr)];hop=int(step/1000*sr)
f,t,Z=stft(seg,sr,nperseg=2048,noverlap=2048-hop,boundary=None);P=np.abs(Z)**2
edges=[60,125,250,500,1000,2000,4000,8000,16000]
print('  ms  '+' '.join('%6d'%e for e in edges[:-1]))
for i in range(P.shape[1]):
    print('%5.0f '%((t[i])*1000)+' '.join('%6.0f'%(10*np.log10(P[(f>=lo)&(f<hi),i].sum()+1e-14)) for lo,hi in zip(edges,edges[1:])))
