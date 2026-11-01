"""L/R correlation and peak of WAVs: python stereo.py a.wav b.wav ..."""
import sys,warnings,numpy as np
warnings.filterwarnings('ignore')
from scipy.io import wavfile
for p in sys.argv[1:]:
    sr,x=wavfile.read(p);x=x.astype(float)[:int(96*sr)];a=x[int(33.2*sr):int(41.9*sr)]
    print('%-50s L/R corr %.3f (held %.3f), peak %.1f dBFS'%(p[-50:],np.corrcoef(x[:,0],x[:,1])[0,1],np.corrcoef(a[:,0],a[:,1])[0,1],20*np.log10(np.abs(x).max()/32768)))
