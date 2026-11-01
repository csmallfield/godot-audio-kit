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
        _,_,ev=parse('%s/loop_0_%d.mid'%(D,sc))
        notes+=[dict(t=sc*32+b,len=l,note=n,vel=v/127) for b,l,n,v in ev if isinstance(n,int)]
    return x,notes
def probe_events(notes):
    """The notes worth fitting: the 1 s holds (scene 2), the velocity pair, short notes every 6 semitones."""
    held=[n for n in notes if 32<=n['t']<44 and n['len']>=0.9]
    vel=[n for n in notes if 64<=n['t']<96 and n['len']>=0.9]
    short=[n for n in notes if n['t']<32 and n['note']%6==0]
    return held+vel+short
def layout(evs,tail=0.9):
    """Place each event in its own slot: (orig_t, new_t, dur) and the render notes."""
    out=[];rn=[];t=0.2
    for e in evs:
        dur=e['len']+tail;out.append((e['t'],t,dur,e));rn.append(dict(time_s=t,note=e['note'],velocity=e['vel'],length_s=e['len']));t+=dur+0.1
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
