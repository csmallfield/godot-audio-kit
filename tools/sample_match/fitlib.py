"""Fit an AKPatch to a scale export by rendering candidates and comparing band energy over time."""
import json,os,subprocess,warnings,numpy as np
warnings.filterwarnings('ignore')
from scipy.io import wavfile
from scipy.signal import stft
from midi import parse
TOOLS=os.path.dirname(os.path.abspath(__file__))
REPO='/Users/smallfch/Documents/GitHub/godot-audio-kit';GD=os.path.expanduser('~/Applications/Godot.app/Contents/MacOS/Godot')
SR=44100
db=lambda v:20*np.log10(np.maximum(v,1e-9))
def load_export(D):
    sr,x=wavfile.read(D+'/stem_0.wav');assert sr==SR
    x=x.astype(np.float64)/32768;notes=[]
    for sc in range(3):
        _,_,ev=parse('%s/loop_0_%d.mid'%(D,sc));ev=[e for e in ev if isinstance(e[2],int)]
        # A loop shorter than the 32-beat scene repeats to fill it (scene 3's is 16 beats).
        L=min([l for l in (4,8,16,32) if l>=max(b+l for b,l,_,_ in ev)-1e-6]+[32])
        notes+=[dict(t=sc*32+r*L+b,len=l,note=n,vel=v/127) for r in range(32//L) for b,l,n,v in ev]
    return x,notes
def probe_events(notes):
    """The notes worth fitting: the 1 s holds (scene 2), the velocity pair, short notes every 6 semitones."""
    held=[n for n in notes if 32<=n['t']<44 and n['len']>=0.9]
    vel=[n for n in notes if 64<=n['t']<96 and n['len']>=0.9]
    short=[n for n in notes if n['t']<32 and n['note']%6==0]
    return held+vel+short
def layout(evs,tail=0.9,notes=None):
    """Place each event in its own slot: (orig_t, new_t, dur) and the render notes. A slot ends at the
    original's next note (when `notes` is given), so it never holds a note the render doesn't play."""
    out=[];rn=[];t=0.2
    for e in evs:
        nxt=min([n['t'] for n in (notes or []) if n['t']>e['t']+1e-3]+[1e9])
        dur=min(e['len']+tail,nxt-e['t']-0.005);out.append((e['t'],t,dur,e));rn.append(dict(time_s=t,note=e['note'],velocity=e['vel'],length_s=e['len']));t+=dur+0.1
    return out,rn,t+0.2
BANDS=np.geomspace(20,16000,31)
def feats(sig_lr,slots,use_new):
    """Per slot: band energy dB [frames x bands] (mid), frames 10 ms."""
    m=sig_lr.mean(1);out=[]
    for ot,nt,dur,e in slots:
        t0=nt if use_new else ot;seg=m[int(t0*SR):int((t0+dur)*SR)]
        f,_,Z=stft(seg,SR,nperseg=2048,noverlap=2048-441,boundary=None);P=np.abs(Z)**2
        B=np.array([P[(f>=lo)&(f<hi)].sum(0) for lo,hi in zip(BANDS[:-1],BANDS[1:])]).T
        out.append(10*np.log10(B+1e-14))
    return out
def loss(FA,FB):
    """Mean abs dB difference, floored 60 dB below the original's peak, level offset removed (returned)."""
    A=np.concatenate(FA);B=np.concatenate(FB);n=min(len(A),len(B));A=A[:n];B=B[:n]
    fl=A.max()-60;A=np.maximum(A,fl);B=np.maximum(B,fl-200)
    w=(A>fl+1).astype(float)+0.15
    off=10*np.log10(np.sum(10**(A/10)))-10*np.log10(np.sum(10**(B/10))+1e-30)
    d=np.abs(np.maximum(B+off,fl)-A);return float(np.sum(d*w)/np.sum(w)),float(off)
def render(cands,notes,length,tag,S):
    jn=S+'/_n_%s.json'%tag;jc=S+'/_c_%s.json'%tag
    json.dump(notes,open(jn,'w'));json.dump(cands,open(jc,'w'))
    r=subprocess.run([GD,'--headless','--path',REPO,'-s',TOOLS+'/render_batch.gd','--',jn,jc,S+'/_r_%s_'%tag,'%.2f'%length],capture_output=True,text=True)
    outs=[]
    for i in range(len(cands)):
        _,y=wavfile.read(S+'/_r_%s_%02d.wav'%(tag,i));outs.append(y.astype(np.float64)/32768)
    return outs

# Harmonic score: band energy can't tell a saw from a square or see a noise layer under a tone, so
# compare each harmonic's level over time, the noise between the harmonics, and the tail.
NOISE_BANDS=[(200,800),(800,2500),(2500,6000),(6000,16000)]
def hfeats(sig_lr,slots,use_new,tr,kmax=40,fmax=12000):
    """Per slot: (harmonic dB [frames x K], noise dB [frames x bands]); 10 ms frames, windows of 4 periods."""
    m=sig_lr.mean(1);out=[]
    for ot,nt,dur,e in slots:
        t0=nt if use_new else ot;seg=m[int(t0*SR):int((t0+dur)*SR)]
        f0=440*2**((e['note']+tr-69)/12);L=int(max(4*SR/f0,512));nfft=int(2**np.ceil(np.log2(2*L)))
        f,_,Z=stft(seg,SR,window='hann',nperseg=L,noverlap=L-441,nfft=nfft,boundary=None,padded=False);P=np.abs(Z)**2
        K=int(min(kmax,fmax//f0));H=np.zeros((P.shape[1],K));mask=np.ones(len(f),bool);df=f[1]
        for k in range(1,K+1):
            lo=int((k-0.3)*f0/df);hi=int((k+0.3)*f0/df)+1;H[:,k-1]=P[lo:hi].max(0)
        for k in range(1,int(16000//f0)+2):
            lo=max(int((k-0.35)*f0/df),0);hi=int((k+0.35)*f0/df)+1;mask[lo:hi]=False
        N=np.array([P[mask&(f>=a)&(f<b)].mean(0)*((f>=a)&(f<b)).sum() if (mask&(f>=a)&(f<b)).any() else np.zeros(P.shape[1]) for a,b in NOISE_BANDS]).T
        out.append((10*np.log10(H+1e-14),10*np.log10(N+1e-14)))
    return out
def hloss(FA,FB,off=None,fl=None):
    """Mean abs dB over harmonics x frames (weighted toward low harmonics), plus the noise between them.
    The level is matched by total harmonic energy (or set by off, with the floor fl); the offset is returned."""
    HA=[a[0] for a in FA];HB=[b[0] for b in FB]
    if off is None:
        ea=sum(np.sum(10**(h/10)) for h in HA);eb=sum(np.sum(10**(h/10)) for h in HB)
        off=10*np.log10(ea)-10*np.log10(eb+1e-30)
    fl=max(h.max() for h in HA)-60 if fl is None else fl
    num=den=0.0;nn=nd=0.0
    for (ha,na),(hb,nb) in zip(FA,FB):
        n=min(len(ha),len(hb));a=np.maximum(ha[:n],fl);b=np.maximum(hb[:n]+off,fl)
        w=((a>fl+1)|(b>fl+1)).astype(float)*(1/np.sqrt(np.arange(1,a.shape[1]+1)))[None,:]
        num+=np.sum(np.abs(a-b)*w);den+=np.sum(w)
        a=np.maximum(na[:n],fl);b=np.maximum(nb[:n]+off,fl);w=((a>fl+1)|(b>fl+1)).astype(float)
        nn+=np.sum(np.abs(a-b)*w);nd+=np.sum(w)
    return float(num/max(den,1e-9)+0.5*nn/max(nd,1e-9)),float(off)
