"""Report on a scale export: python analyze.py <dir with stem_0.wav and loop_0_*.mid>"""
import sys,json,warnings,numpy as np
warnings.filterwarnings('ignore')
from scipy.io import wavfile
from scipy.signal import hilbert,butter,sosfiltfilt,stft
sys.path.insert(0,__file__.rsplit('/',1)[0]);from midi import parse
D=sys.argv[1]
sr,x=wavfile.read(D+'/stem_0.wav');x=x.astype(np.float64)/32768
x=sosfiltfilt(butter(2,15,"highpass",fs=sr,output="sos"),x,axis=0)
L,R=x[:,0],x[:,1];m=(L+R)/2
db=lambda v:20*np.log10(np.maximum(v,1e-9))
nf=lambda n:440*2**((n-69)/12)
notes=[]
for sc in range(3):
    _,_,ev=parse('%s/loop_0_%d.mid'%(D,sc))
    notes+=[dict(t=sc*32+b,len=l,note=n,vel=v) for b,l,n,v in ev if isinstance(n,int)]
print('== file: %.1f s, peak %.1f dBFS'%(len(m)/sr,db(np.abs(x).max())))
side=(L-R)/2;print('stereo: L/R corr %.4f, side/mid %.1f dB'%(np.corrcoef(L,R)[0,1],db(np.std(side))-db(np.std(m))))
N=1<<17;F=np.fft.rfftfreq(N,1/sr)
def spec(t0,t1,sig=m):
    seg=sig[int(t0*sr):int(t1*sr)];w=np.hanning(len(seg));return np.abs(np.fft.rfft(seg*w,N))*2/w.sum()
def peak_near(S,f,tol=0.03):
    sel=(F>f*(1-tol))&(F<f*(1+tol));i=np.argmax(np.where(sel,S,0));return F[i],S[i]
def harmonics(S,f0,nh=10):return np.array([peak_near(S,k*f0)[1] if k*f0<sr/2-300 else 1e-9 for k in range(1,nh+1)])
# 1. transposition: which octave offset explains the spectrum (energy at subharmonic f0)
chrom=[n for n in notes if n['t']<32]
votes={}
for n in chrom[::5]:
    S=spec(n['t']+0.03,n['t']+0.24)
    for off in [-36,-24,-12,0,12]:
        f0=nf(n['note']+off)
        if f0<15 or f0>sr/2:continue
        h=harmonics(S,f0,8);_,top=peak_near(S,nf(n['note']+off),0.05)
        votes.setdefault(off,[]).append(db(top)-db(S.max()))
off=max(votes,key=lambda k:(np.mean(np.array(votes[k])>-20),k*0- (abs(k))*0, -k))
# choose the lowest offset whose fundamental is consistently present (within 20 dB of the strongest peak)
cands=[k for k in sorted(votes) if np.mean(np.array(votes[k])>-30)>0.8]
off=cands[0] if cands else 0
print('transpose: %+d semitones (MIDI 60 sounds at %.1f Hz)'%(off,nf(60+off)))
# 2. per-note table
print('\n-- chromatic run: note, cents, rms dB, h2..h6 rel h1, noise dB (non-harmonic energy rel total), centroid Hz')
rows=[]
for n in chrom:
    f0=nf(n['note']+off);S=spec(n['t']+0.03,n['t']+0.24)
    fp,_=peak_near(S,f0);h=harmonics(S,f0,40)
    tot=np.sum(S[F<min(16000,sr/2)]**2);harm=0
    for k in range(1,200):
        if k*f0>16000:break
        sel=(F>k*f0-max(6,f0*0.04))&(F<k*f0+max(6,f0*0.04));harm+=np.sum(S[sel]**2)
    seg=m[int((n['t']+0.03)*sr):int((n['t']+0.24)*sr)]
    cen=np.sum(F*S**2)/np.sum(S**2)
    rows.append(dict(note=n['note'],cents=1200*np.log2(fp/f0),rms=db(np.sqrt(np.mean(seg**2))),rel=db(h[1:6])-db(h[0]),noise=10*np.log10(max(tot-harm,1e-12)/tot),cen=cen,h=db(h)))
for r in rows:print('%3d %+4.0f %6.1f | %s | %5.1f | %5.0f'%(r['note'],r['cents'],r['rms'],' '.join('%5.1f'%v for v in r['rel']),r['noise'],r['cen']))
# zones: consecutive notes with near-identical harmonic ratios
zones=[[rows[0]['note']]]
for a,b in zip(rows,rows[1:]):
    if np.max(np.abs(a['rel'][:3]-b['rel'][:3]))<0.6 and abs(a['rms']-b['rms'])<0.6:zones[-1].append(b['note'])
    else:zones.append([b['note']])
big=[z for z in zones if len(z)>=3]
print('\nzones (identical timbre across >=3 neighbours): %d of %d notes in %d zones -> %s'%(sum(len(z) for z in big),len(rows),len(big),'SAMPLED (key zones)' if sum(len(z) for z in big)>len(rows)*0.6 else 'continuous'))
print(' ',', '.join('%d-%d'%(z[-1],z[0]) for z in big))
# 3. envelope on held notes (scene 2: 1 s holds at 33,35,37,39,41)
print('\n-- held notes (1 s): level dB rel peak at ms; release times')
held=[n for n in notes if 32<=n['t']<44 and n['len']>=0.9]
for n in held:
    f0=nf(n['note']+off);win=max(0.003,2.0/f0)
    hop=int(0.001*sr);a=int((n['t']-0.01)*sr);b=int((n['t']+1.9)*sr);seg=m[a:b]
    w=int(win*sr);e=np.sqrt(np.convolve(seg**2,np.ones(w)/w,'same'))[::hop];E=db(e)
    i0=10;pk=np.argmax(E[i0:i0+1000])+i0;P=E[pk]
    def at(ms):return E[i0+ms]-P
    rel=E[i0+1000:]-E[i0+995]
    def tdown(dbv):
        j=np.where(rel<dbv)[0];return j[0] if len(j) else None
    t10=next((k for k in range(0,300) if E[i0+k]-P>-10),None)
    print(' %3d (%.0f Hz) peak@%3dms  -10dB reached@%sms | %s | release to -20dB %s ms, -40dB %s ms, -60dB %s ms'%(n['note'],f0,pk-i0,t10,
        ' '.join('%d:%.1f'%(ms,at(ms)) for ms in [20,50,100,200,400,700,990]),tdown(-20),tdown(-40),tdown(-60)))
# 4. brightness and pitch over a held note (the middle one)
print('\n-- over held notes: centroid Hz and pitch cents at ms')
for n in held:
    f0=nf(n['note']+off);out=[];pc=[]
    for ms in [5,20,50,100,200,400,700,950]:
        t=n['t']+ms/1000;w=max(0.02,4/f0)
        S=spec(t,t+w);out.append(np.sum(F*S**2)/np.sum(S**2))
        Sx=spec(t,t+max(0.05,8/f0));fp,_=peak_near(Sx,f0,0.06);pc.append(1200*np.log2(fp/f0))
    print(' %3d centroid %s | cents %s'%(n['note'],' '.join('%5.0f'%v for v in out),' '.join('%+4.0f'%v for v in pc)))
# 5. amplitude/pitch modulation on the longest held note: envelope modulation spectrum
n=held[2];f0=nf(n['note']+off)
seg=m[int((n['t']+0.15)*sr):int((n['t']+0.98)*sr)];env=np.abs(hilbert(seg));env=sosfiltfilt(butter(2,40,fs=sr,output='sos'),env)
E=np.abs(np.fft.rfft((env-env.mean())*np.hanning(len(env)),1<<16));Fe=np.fft.rfftfreq(1<<16,1/sr)
sel=(Fe>0.8)&(Fe<30);i=np.argmax(np.where(sel,E,0))
print('\n-- tremolo: strongest loudness wobble %.1f Hz, depth %.1f%% (note %d)'%(Fe[i],100*2*E[i]/np.sum(np.hanning(len(env)))/env.mean(),n['note']))
# 6. velocity: scene 3 note 84, 1 s holds at 64+3 (127) and 64+7 (64)
a=[n for n in notes if 64<=n['t']<96 and n['len']>=0.9]
if len(a)>=2:
    S1=spec(a[0]['t']+0.1,a[0]['t']+0.8);S2=spec(a[1]['t']+0.1,a[1]['t']+0.8)
    c1=np.sum(F*S1**2)/np.sum(S1**2);c2=np.sum(F*S2**2)/np.sum(S2**2)
    print('-- velocity %d vs %d: level %.1f dB, centroid %.0f vs %.0f Hz'%(a[0]['vel'],a[1]['vel'],db(np.sqrt(np.sum(S1**2)))-db(np.sqrt(np.sum(S2**2))),c1,c2))
# 7. tails beyond the release: energy 100-400 ms after a held note ends
for n in held[:3]:
    e=lambda t0,t1:db(np.sqrt(np.mean(m[int(t0*sr):int(t1*sr)]**2)))
    end=n['t']+n['len'];print('-- tail after note %d: -%.0f..%.0f ms: %s dB'%(n['note'],0,600,' '.join('%.0f'%(e(end+k/1000,end+k/1000+0.05)-e(end-0.1,end)) for k in [0,50,100,200,400,550])))
json.dump(dict(transpose=off,rows=[{k:(v.tolist() if hasattr(v,'tolist') else v) for k,v in r.items()} for r in rows],zones=big),open(D+'/report.json','w'))
