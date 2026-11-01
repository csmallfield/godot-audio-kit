"""python resynth.py <export dir> <transpose> <out.json> [frames] [zone step]
A patch built from the recording itself: a table oscillator whose key zones hold cycles taken from the
held notes at times through the note (swept by env2), keeping their levels, so the waveform, the
decay and the level across the keyboard are the recording's own. The release, the velocity
curve and the tuning are measured."""
import sys,json;sys.path.insert(0,__file__.rsplit('/',1)[0])
from fitlib import *
D,TR,OUT=sys.argv[1],float(sys.argv[2]),sys.argv[3];NF=int(sys.argv[4]) if len(sys.argv)>4 else 12
x,notes=load_export(D);m=x.mean(1)
from scipy.signal import butter,sosfiltfilt
m=sosfiltfilt(butter(2,15,'hp',fs=SR,output='sos'),m)
def refine(seg,fg):
    n=len(seg);X=np.abs(np.fft.rfft(seg*np.hanning(n),8*n));f=np.fft.rfftfreq(8*n,1/SR);best=fg;bs=-1
    for c in np.linspace(fg*0.985,fg*1.015,241):
        s=sum(np.interp(c*k,f,X) for k in range(1,6))
        if s>bs:bs=s;best=c
    return best
def cycle_at(seg,f0,t,K):
    """Complex amplitude of harmonics 1..K around time t (window of 2 periods, at least 6 ms)."""
    W=int(max(2*SR/f0,0.006*SR));c=int(t*SR);a=max(c-W//2,0);w=np.hanning(W);s=seg[a:a+W]
    if len(s)<W:s=np.pad(s,(0,W-len(s)))
    tt=(np.arange(W)+a)/SR;w=w/w.sum();k=np.arange(1,K+1)[:,None]
    return 2*(np.exp(-2j*np.pi*k*f0*tt[None,:])@(s*w))
# Zones: every STEP semitones along the chromatic run (scene 1, every note, 1/4 s held, 1/2 s apart),
# plus the held notes (scene 2, 1 s). A run note gives the frames up to JOIN s; the rest come from
# the nearest held note, scaled to meet it, with the run note's phases so the frames line up.
STEP=int(sys.argv[5]) if len(sys.argv)>5 else 3;JOIN=0.2
holds=sorted([n for n in notes if 32<=n['t']<44 and n['len']>=0.9],key=lambda n:n['note'])
run={n['note']:n for n in notes if n['t']<32}
# Position through the note: W x (1 - exp(-t/TAU)) (env2: detail in the attack) + (1 - W) x t/T (env3: even
# spacing later); frames sit where it crosses i/(NF-1). Both envelopes hold through the release.
W,TAU,T=0.5,0.08,1.0
pos=lambda t:W*(1-np.exp(-t/TAU))+(1-W)*min(t/T,1)
tg=np.linspace(0,T,20001);pg=np.array([pos(t) for t in tg])
times=[float(np.interp(i/(NF-1),pg,tg)) for i in range(NF)];times[-1]=min(times[-1],0.97)
# Wide sounds (left/right correlation under 0.95 on the held notes) get a table per side, panned hard.
cor=[]
for h in holds:
    l,r=x[int((h['t']+.05)*SR):int((h['t']+.95)*SR)].T;cor.append(np.dot(l,r)/np.sqrt(np.dot(l,l)*np.dot(r,r)+1e-20))
STEREO=np.mean(cor)<0.95
CH=[x[:,0]-np.mean(x[:,0]),x[:,1]-np.mean(x[:,1])] if STEREO else [m]
CH=[sosfiltfilt(butter(2,15,'hp',fs=SR,output='sos'),c) for c in CH] if STEREO else CH
def measure(n,ts):
    """Per channel, the frames at times ts, all turned by the mid channel's fundamental (phase 0 there),
    so the frames line up through the note and left and right keep their relation."""
    a,b=int(n['t']*SR),int((n['t']+1.5)*SR);fg=440*2**((n['note']+TR-69)/12)
    f0=refine(m[a:b][int(.03*SR):int((min(n['len'],0.9))*SR)],fg);K=int(min(511,18000/f0))
    out=[[] for _ in CH]
    for t in ts:
        rot=np.exp(-1j*np.arange(1,K+1)*np.angle(cycle_at(m[a:b],f0,max(t,1.0/f0),1)[0]))
        for c,ch in enumerate(CH):out[c].append(cycle_at(ch[a:b],f0,max(t,1.0/f0),K)*rot)
    return f0,fg,out
def frame(A):
    amp=np.abs(A);keep=amp>amp.max()*10**(-80/20);amp=np.where(keep,amp,0);last=int(np.nonzero(keep)[0].max())+1
    ph=((np.angle(A)+np.pi/2)/(2*np.pi))%1   # a cos(theta + phi) = a sin(theta + phi + pi/2), in cycles
    return {'harmonics':[float('%.4g'%v) for v in amp[:last]],'phases':[float('%.4f'%v) for v in ph[:last]]}
def peak(fr):
    """A frame's full-band cycle peak, as AKWavetables builds it."""
    h=np.array(fr['harmonics']);p=np.array(fr['phases']);t=np.arange(1024)/1024
    return np.abs(np.sum(h[:,None]*np.sin(2*np.pi*(np.arange(1,len(h)+1)[:,None]*t[None,:]+p[:,None])),0)).max()
H={h['note']:measure(h,times) for h in holds}
keys=sorted(set([k for k in run if (k-holds[0]['note'])%STEP==0]+list(H)))
zones=[[] for _ in CH];cents=[]
for k in keys:
    if k in H:
        f0,fg,F=H[k];cents.append(1200*np.log2(f0/fg))
    else:
        f0,fg,F=measure(run[k],[t for t in times if t<=JOIN]);hk=min(H,key=lambda h:abs(h-k))
        _,_,G=H[hk];j=len(F[0])-1
        # Scale the held note to meet the run note at JOIN (one gain for both sides), keeping the run note's phases.
        g=np.sqrt(sum(np.sum(np.abs(Fc[j])**2) for Fc in F)/max(sum(np.sum(np.abs(Gc[j])**2) for Gc in G),1e-30))
        for Fc,Gc in zip(F,G):
            K=len(Fc[j]);ph=np.exp(1j*np.angle(Fc[j]))
            for i in range(len(Fc),len(times)):
                a=np.zeros(K);gk=np.abs(Gc[i])[:K];a[:len(gk)]=gk;Fc.append(a*g*ph)
    for c in range(len(CH)):zones[c].append({'key':k,'frames':[frame(A) for A in F[c]]})
det=float(np.median(cents))
# Release: the level's time constant after note-off, on the held notes.
rels=[]
for n in holds:
    a=int((n['t']+n['len'])*SR);e=np.sqrt(np.convolve(m[a-2000:a+int(.6*SR)]**2,np.ones(441)/441,'same'))
    e0=e[2000];k=np.nonzero(e[2000:]<e0*np.exp(-1))[0]
    if e0>1e-4 and len(k):rels.append(k[0]/SR)
rel=float(np.median(rels)) if rels else 0.05
# Velocity: 127 against 64, the level ratio on the long pair (scene 3).
vp=sorted([n for n in notes if 64<=n['t']<96 and n['len']>=0.9],key=lambda n:n['t'])[:2]
lv=[np.sqrt(np.mean(m[int((n['t']+.01)*SR):int((n['t']+.3)*SR)]**2)) for n in vp]
hi,lo=(lv[0],lv[1]) if vp[0]['vel']>vp[1]['vel'] else (lv[1],lv[0]);vr=sorted([vp[0]['vel'],vp[1]['vel']])
vcurve=float(np.clip(np.log(lo/hi)/np.log(vr[0]/vr[1]),0.25,4)) if hi>0 and lo>0 else 1.0
pk=[max(peak(f) for z in zc for f in z['frames']) for zc in zones]
oscs=[{'shape':'table','table':{'zones':zc,'normalize':False,'blend':False},'semitones':TR,'cents':det,'position':W,
       'level':(0.7071 if STEREO else 1.0)*p/max(pk),'pan':([-1.0,1.0][c] if STEREO else 0.0)} for c,(zc,p) in enumerate(zip(zones,pk))]
patch={'oscillators':oscs,
 'filter':{'type':'off'},'amp_env':{'attack_s':0.0,'decay_s':0.0,'sustain':1.0,'release_s':max(rel/1.0,0.002),'curve':'exp'},
 'env2':{'attack_s':0.0,'decay_s':TAU,'sustain':0.0,'release_s':1000.0,'curve':'exp'},
 'env3':{'attack_s':T,'decay_s':0.0,'sustain':1.0,'release_s':1000.0},
 'mods':[{'source':'env2','dest':'osc.position','amount':-W},{'source':'env3','dest':'osc.position','amount':1-W}],'velocity_sens':1.0,'velocity_curve':vcurve,'polyphony':16,'mode':'poly'}
json.dump(patch,open(OUT,'w'))
print(('stereo ' if STEREO else 'mono ')+'zones %s (%d), %d frames, tuning %+.1f cents, release %.3f s, velocity curve %.2f, %d kB'%([z['key'] for z in zones[0]],len(zones[0]),NF,det,rel,vcurve,len(json.dumps(patch))//1024))
