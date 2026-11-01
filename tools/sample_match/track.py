"""Pitch and level track through a held note: python track.py <dir> <onset s> <note> [step ms] [dur s]
Prints, every step: level dB, the strongest peak (Hz, semitones from the note) and the next two."""
import sys,warnings,numpy as np
warnings.filterwarnings('ignore')
from scipy.io import wavfile
from scipy.signal import butter,sosfiltfilt,find_peaks
D,t0,note=sys.argv[1],float(sys.argv[2]),int(sys.argv[3]);step=float(sys.argv[4]) if len(sys.argv)>4 else 10;dur=float(sys.argv[5]) if len(sys.argv)>5 else 1.3
sr,x=wavfile.read(D+'/stem_0.wav');m=x.astype(np.float64).mean(1)/32768;m=sosfiltfilt(butter(2,15,'highpass',fs=sr,output='sos'),m)
f0=440*2**((note-69)/12);W=int(0.03*sr);N=1<<16;F=np.fft.rfftfreq(N,1/sr)
for k in range(int(dur*1000/step)):
    a=int((t0+k*step/1000)*sr);seg=m[a:a+W];S=np.abs(np.fft.rfft(seg*np.hanning(W),N));d=20*np.log10(S/S.max()+1e-12)
    p,_=find_peaks(d,height=-25,distance=int(20/F[1]));p=p[np.argsort(-d[p])][:3]
    lv=20*np.log10(np.sqrt(np.mean(seg**2))+1e-9)
    print('%5d ms %6.1f dB |'%(k*step,lv),'  '.join('%6.0f Hz %+5.1f st'%(F[i],12*np.log2(F[i]/f0)) for i in p))
