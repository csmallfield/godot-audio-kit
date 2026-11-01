"""Build an A/B clip, original then match per passage: python ab.py original.wav match.wav out.wav"""
import sys,warnings,numpy as np
warnings.filterwarnings('ignore')
from scipy.io import wavfile
sr,o=wavfile.read(sys.argv[1]);_,m=wavfile.read(sys.argv[2]);o=o.astype(float);m=m.astype(float);gap=np.zeros((int(0.8*sr),2));parts=[]
for a,b in [(16.9,32.0),(32.9,42.8),(85.8,90.8),(64.9,72.8)]:parts+=[o[int(a*sr):int(b*sr)],gap,m[int(a*sr):int(b*sr)],gap,gap]
wavfile.write(sys.argv[3],sr,np.concatenate(parts).astype(np.int16))
