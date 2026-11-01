"""Times of high-band (>4 kHz) bursts in the 1 s holds: python bursts.py file.wav"""
import sys,warnings,numpy as np
warnings.filterwarnings('ignore')
from scipy.io import wavfile
from scipy.signal import butter,sosfiltfilt,find_peaks
sr,x=wavfile.read(sys.argv[1]);m=x.astype(float).mean(1)/32768
h=sosfiltfilt(butter(4,4000,'highpass',fs=sr,output='sos'),m);e=np.sqrt(np.convolve(h**2,np.ones(220)/220,'same'))
for t,n in [(33,96),(37,72),(41,48)]:
    seg=20*np.log10(e[int(t*sr):int((t+1.0)*sr)]+1e-9);p,_=find_peaks(seg,height=seg.max()-25,distance=int(0.03*sr))
    print(' %s: bursts at ms %s, peak %.0f dB'%(n,[int(i/sr*1000) for i in p],seg.max()))
