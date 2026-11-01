import sys,warnings,numpy as np
warnings.filterwarnings('ignore')
from scipy.io import wavfile
from scipy.signal import find_peaks,butter,sosfiltfilt
D=sys.argv[1];off=int(sys.argv[2])
sr,x=wavfile.read(D+'/stem_0.wav');x=x.astype(np.float64)/32768;m=x.mean(1);L,R=x[:,0],x[:,1]
db=lambda v:20*np.log10(np.maximum(v,1e-9));nf=lambda n:440*2**((n-69)/12)
N=1<<20;F=np.fft.rfftfreq(N,1/sr)
# detune: held note 96 (t=33..34), fine spectrum around each of first 4 harmonics
f0=nf(96+off);seg=m[int(33.15*sr):int(33.98*sr)];S=np.abs(np.fft.rfft(seg*np.blackman(len(seg)),N));d=db(S/S.max())
print('detune around harmonics of held note 96 (%.1f Hz): peaks (cents from k*f0, dB)'%f0)
for k in [1,2,3,4]:
    sel=np.where((F>k*f0*0.96)&(F<k*f0*1.04))[0];p,_=find_peaks(d[sel],height=-50,distance=int(1.0/F[1]))
    print('  h%d'%k,' '.join('%+.0fc(%.0f)'%(1200*np.log2(F[sel][i]/(k*f0)),d[sel][i]) for i in p))
# L vs R spectra (different voices panned?)
for nm,ch in [('L',L),('R',R)]:
    seg=ch[int(33.15*sr):int(33.98*sr)];S=np.abs(np.fft.rfft(seg*np.blackman(len(seg)),N));dd=db(S)
    sel=np.where((F>f0*0.96)&(F<f0*1.04))[0];p,_=find_peaks(dd[sel],height=dd[sel].max()-40)
    print('  %s h1:'%nm,' '.join('%+.0fc(%.0f)'%(1200*np.log2(F[sel][i]/f0),dd[sel][i]) for i in p))
# tail after scene-2 note 96 release (t=34.0): 10ms rms envelope over 1 s, and its autocorrelation (echo spacing)
hop=int(0.005*sr);seg=m[int(34.0*sr):int(35.0*sr)];e=np.sqrt(np.convolve(seg**2,np.ones(hop)/hop,'same'))[::hop]
print('tail envelope after release, dB every 25 ms:',' '.join('%.0f'%v for v in db(e[::5])))
# compare tail L/R correlation (reverb decorrelates)
a,b=L[int(34.15*sr):int(34.9*sr)],R[int(34.15*sr):int(34.9*sr)];print('tail L/R corr %.2f; held part L/R corr %.2f'%(np.corrcoef(a,b)[0,1],np.corrcoef(L[int(33.2*sr):int(33.9*sr)],R[int(33.2*sr):int(33.9*sr)])[0,1]))
# echo: autocorrelation of the tail signal
ac=np.correlate(e-e.mean(),e-e.mean(),'full')[len(e)-1:];ac/=ac[0];p,_=find_peaks(ac,height=0.2)
print('tail envelope autocorr peaks (ms):',[int(i*5) for i in p[:6]])
# noise: residual between harmonics on held note 60, spectrum in bands
f0=nf(60+off);seg=m[int(39.2*sr):int(39.9*sr)];S=np.abs(np.fft.rfft(seg*np.hanning(len(seg)),N))
mask=np.ones_like(F,bool)
for k in range(1,3000):
    if k*f0>20000:break
    mask&=~((F>k*f0-4)&(F<k*f0+4))
bands=[50,100,200,400,800,1600,3200,6400,12800,20000]
print('held note 60 harmonic vs between-harmonic energy by band (dB):')
for lo,hi in zip(bands,bands[1:]):
    b=(F>=lo)&(F<hi);h=np.sum(S[b&~mask]**2);n=np.sum(S[b&mask]**2)
    print('  %5d-%5d harm %6.1f  noise %6.1f'%(lo,hi,10*np.log10(h+1e-12),10*np.log10(n+1e-12)))
# velocity: harmonic levels note 84 vel127 vs vel64 (scene 3 1s holds at 67, 71)
f0=nf(84+off)
for t,lab in [(67.1,'127'),(71.1,' 64')]:
    seg=m[int(t*sr):int((t+0.8)*sr)];S=np.abs(np.fft.rfft(seg*np.hanning(len(seg)),N))*2/np.hanning(len(seg)).sum()
    h=[S[(F>k*f0*0.97)&(F<k*f0*1.03)].max() for k in range(1,13)]
    print('  vel',lab,' '.join('%5.1f'%v for v in db(np.array(h))))
