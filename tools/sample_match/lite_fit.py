"""python lite_fit.py <export dir> <transpose> full.json <center key> out.json [frames]: a light version of a
resynthesis patch. One key zone (nearest <center key>) plays the whole keyboard. Away from it, the
recording's tone mostly follows a filter fixed in Hz, not the harmonic numbers, so a low-pass with part key
tracking is fitted (cutoff, Q, tracking, and key -> amp for the level), and the zone's frames are divided by
that filter's response at the center so the center note stays exact. The fit runs on the one-zone render's
harmonics with the filter applied in dB, then the result is rendered and checked."""
import sys,json,subprocess;sys.path.insert(0,__file__.rsplit('/',1)[0])
from fitlib import *
from scipy.io import wavfile
from scipy.optimize import minimize
D,TR,FULL,C,OUT=sys.argv[1],float(sys.argv[2]),sys.argv[3],int(sys.argv[4]),sys.argv[5];NF=sys.argv[6] if len(sys.argv)>6 else ''
T=TOOLS;PY=sys.executable;BASE=OUT[:-5]
subprocess.run([PY,T+'/lite.py',FULL,BASE+'_raw.json',str(C)]+([NF] if NF else []),check=True,capture_output=True)
subprocess.run([PY,T+'/render_full.py',D,BASE+'_raw.json',BASE+'_raw.wav'],check=True,capture_output=True)
x,notes=load_export(D);p=json.load(open(BASE+'_raw.json'))
evs=[n for n in notes if n['len']>=0.2 and n['t']<44];ts=sorted(set(n['t'] for n in notes))
slots=[(e['t'],e['t'],min(e['len']+0.9,min([t for t in ts if t>e['t']+1e-3]+[96.3])-e['t']-0.005),e) for e in evs]
HA=hfeats(x,slots,False,TR);_,y=wavfile.read(BASE+'_raw.wav');HB=hfeats(y.astype(np.float64)/32768,slots,True,TR)
cents=next(o['cents'] for o in p['oscillators'] if o['shape']=='table')
f0=lambda n:440*2**((n+TR+cents/100-69)/12)
def H(f,fc,q):r=f/fc;return 1/np.sqrt((1-r*r)**2+(r/q)**2)
# The cutoff moves through the note with the same two envelopes that sweep the table: env2 (exponential,
# 0.08 s) and env3 (a 1 s ramp), so a filter envelope costs no new parts. Both hold through the release.
E2=lambda t:np.exp(-np.asarray(t)/0.08);E3=lambda t:np.minimum(np.asarray(t),1.0)
def cut(v,n,t):return np.clip(np.exp(v[0])*2**(v[1]*(n-60)/12+v[4]*E2(t)+v[5]*E3(t)),20,20000)
# Times of the analysis frames (hfeats: hop 441, window of 4 periods) and of the table frames.
FT=[(np.arange(h.shape[0])*441+max(4*SR/(440*2**((s[3]['note']+TR-69)/12)),512)/2)/SR for (h,_),s in zip(HB,slots)]
tg=np.linspace(0,1,20001);pg=0.5*(1-np.exp(-tg/0.08))+0.5*tg
def corr(v,n,t):
    q,a=np.exp(v[2]),v[3];kc=(C-60)/12;kn=(n-60)/12
    g=max(1+a*kn,1e-3)/max(1+a*kc,1e-3);K=np.arange(1,41)[None,:];t=np.asarray(t)[:,None]
    hc=np.maximum(H(K*f0(C),cut(v,C,t),q),10**(-24/20))
    return 20*np.log10(H(K*f0(n),cut(v,n,t),q)/hc*g)
def L(v):
    if not(-0.25<v[3]<0.6 and -1.0<v[1]<1.2 and np.log(40)<v[0]<np.log(18000) and np.log(0.3)<v[2]<np.log(3) and abs(v[4])<9 and abs(v[5])<9):return 99
    FB=[(h+corr(v,s[3]['note'],t)[:,:h.shape[1]],nz) for (h,nz),s,t in zip(HB,slots,FT)];return hloss(HA,FB)[0]
best=None
for c0 in [300,1000,3000,8000]:
    for e0 in [(0,0),(2,0),(0,-1)]:
        r=minimize(L,[np.log(c0),0.3,np.log(0.707),0.1,e0[0],e0[1]],method='Nelder-Mead',options={'maxiter':600,'xatol':1e-3,'fatol':1e-3})
        if best is None or r.fun<best.fun:best=r
v=best.x;fc,amt,q,a=float(np.exp(v[0])),float(v[1]),float(np.exp(v[2])),float(v[3])
print('raw %.1f -> fitted %.1f: cutoff %.0f Hz, Q %.2f, key tracking %.2f, key -> amp %+.2f, env2 %+.2f oct, env3 %+.2f oct'%(hloss(HA,HB)[0],best.fun,fc,q,amt,a,v[4],v[5]))
# Then a fixed curve in Hz: patch EQ effects after the voices (each a low shelf, a peak and a high shelf,
# the engine's own biquads), fitted on top of the filter. A fixed EQ moves with frequency, not the note, so
# it reshapes notes away from the center while the center is divided by it below.
NEQ=int(os.environ.get('LITE_EQ','2'))
def biq(b,a,f):
    z=np.exp(-2j*np.pi*np.asarray(f)/SR);return (b[0]+b[1]*z+b[2]*z*z)/(a[0]+a[1]*z+a[2]*z*z)
def shelf(f0_,g,high,f):
    A=10**(g/40);w=2*np.pi*f0_/SR;cw,sw=np.cos(w),np.sin(w);t=2*np.sqrt(A)*sw/2*np.sqrt(2)
    if not high:return biq([A*((A+1)-(A-1)*cw+t),2*A*((A-1)-(A+1)*cw),A*((A+1)-(A-1)*cw-t)],[(A+1)+(A-1)*cw+t,-2*((A-1)+(A+1)*cw),(A+1)+(A-1)*cw-t],f)
    return biq([A*((A+1)+(A-1)*cw+t),-2*A*((A-1)+(A+1)*cw),A*((A+1)+(A-1)*cw-t)],[(A+1)-(A-1)*cw+t,2*((A-1)-(A+1)*cw),(A+1)-(A-1)*cw-t],f)
def peakf(f0_,g,q,f):
    A=10**(g/40);w=2*np.pi*f0_/SR;al=np.sin(w)/(2*q);return biq([1+al*A,-2*np.cos(w),1-al*A],[1+al/A,-2*np.cos(w),1-al/A],f)
def eqs(pe):
    return [dict(type='eq',low_hz=float(np.exp(pe[i*7])),low_db=float(pe[i*7+1]),mid_hz=float(np.exp(pe[i*7+2])),mid_db=float(pe[i*7+3]),
                 mid_q=float(np.exp(pe[i*7+4])),high_hz=float(np.exp(pe[i*7+5])),high_db=float(pe[i*7+6])) for i in range(NEQ)]
def Heq(pe,f):
    h=np.ones(np.shape(f),complex)
    for e in eqs(pe):h=h*shelf(e['low_hz'],e['low_db'],False,f)*peakf(e['mid_hz'],e['mid_db'],e['mid_q'],f)*shelf(e['high_hz'],e['high_db'],True,f)
    return h
FV=[(h+corr(v,s[3]['note'],t)[:,:h.shape[1]],nz) for (h,nz),s,t in zip(HB,slots,FT)]
def LE(pe):
    e=eqs(pe)
    if any(not(20<d[k]<18000) for d in e for k in('low_hz','mid_hz','high_hz')) or any(abs(d[k])>24 for d in e for k in('low_db','mid_db','high_db')) or any(not(0.2<d['mid_q']<4) for d in e):return 99
    out=[]
    for (h,nz),s in zip(FV,slots):
        K=np.arange(1,h.shape[1]+1);out.append((h+20*np.log10(np.abs(Heq(pe,K*f0(s[3]['note'])))/np.maximum(np.abs(Heq(pe,K*f0(C))),10**(-24/20)))[None,:],nz))
    return hloss(HA,out)[0]
pe=np.array([v for i in range(NEQ) for v in (np.log([60,120][i%2]),0,np.log([400,1500][i%2]),0,np.log(0.7),np.log([3000,8000][i%2]),0)])
if NEQ:
    r=minimize(LE,pe,method='Powell',options={'maxiter':4000,'xtol':1e-3,'ftol':1e-4});pe=r.x
    print('EQ: %.1f -> %.1f: '%(best.fun,r.fun)+'; '.join('low %.0f Hz %+.1f, mid %.0f Hz %+.1f Q %.2f, high %.0f Hz %+.1f'%(e['low_hz'],e['low_db'],e['mid_hz'],e['mid_db'],e['mid_q'],e['high_hz'],e['high_db']) for e in eqs(pe)))
# Last, the level by key (key_levels: a point every 6 semitones, straight lines in dB between them),
# for the level changes across the keyboard that neither curve follows.
def eqdb(n,K):return 20*np.log10(np.abs(Heq(pe,K*f0(n)))/np.maximum(np.abs(Heq(pe,K*f0(C))),10**(-24/20))) if NEQ else 0*K
FE=[]
for (h,nz),s in zip(FV,slots):
    K=np.arange(1,h.shape[1]+1);FE.append((h+eqdb(s[3]['note'],K)[None,:],nz))
KP=np.arange(min(s[3]['note'] for s in slots)//6*6,max(s[3]['note'] for s in slots)+6,6)
NK=np.array([s[3]['note'] for s in slots])
def LK(kd):
    if np.abs(kd).max()>40:return 99
    g=np.interp(NK,KP,kd);return hloss(HA,[(h+gi,nz) for (h,nz),gi in zip(FE,g)])[0]
_,off=hloss(HA,FE)
d0=np.array([10*np.log10(np.sum(10**(a[0]/10))/np.sum(10**((b[0]+off)/10))) for a,b in zip(HA,FE)])
kd=np.array([np.median(d0[np.abs(NK-k)<=3]) if (np.abs(NK-k)<=3).any() else 0 for k in KP])
r=minimize(LK,kd,method='Powell',options={'maxiter':3000,'xtol':1e-2,'ftol':1e-4});kd=r.x-np.interp(C,KP,r.x)
print('key levels: %.1f -> %.1f: '%(hloss(HA,FE)[0],r.fun)+' '.join('%d:%+.1f'%(k,d) for k,d in zip(KP,kd)))
p['key_levels']=[[int(k),round(float(d),2)] for k,d in zip(KP,kd)]
kc=(C-60)/12
def peak(frs):
    t=np.arange(1024)/1024;pk=0
    for fr in frs:
        h=np.array(fr['harmonics']);ph=np.array(fr['phases'])
        pk=max(pk,np.abs(np.sum(h[:,None]*np.sin(2*np.pi*(np.arange(1,len(h)+1)[:,None]*t[None,:]+ph[:,None])),0)).max())
    return pk
for o in p['oscillators']:
    t=o.get('table')
    if not isinstance(t,dict):continue
    p0=peak(t['zones'][0]['frames'])
    frs=t['zones'][0]['frames'];ft=[float(np.interp(i/(len(frs)-1),pg,tg)) for i in range(len(frs))];ft[-1]=min(ft[-1],0.97)
    for j,fr in enumerate(frs):
        # Divide by the filter's complex response, so the center note keeps its phases (its waveform) too.
        K=np.arange(1,len(fr['harmonics'])+1);sj=1j*K*f0(C)/cut(v,C,ft[j]);Hc=1/(sj*sj+sj/q+1)
        if NEQ:Hc=Hc*Heq(pe,K*f0(C))
        hc=np.maximum(np.abs(Hc),10**(-24/20))
        fr['harmonics']=[float('%.4g'%v) for v in np.array(fr['harmonics'])/hc]
        fr['phases']=[float('%.4f'%v) for v in (np.array(fr['phases'])-np.angle(Hc)/(2*np.pi))%1]
    # The engine scales a table with normalize = false by its peak; keep the level the division changed.
    o['level']=o['level']*peak(t['zones'][0]['frames'])/p0/max(1+a*kc,1e-3)
p['filter']={'type':'lowpass','cutoff_hz':fc,'q':q,'slope_db':12.0}
p['mods']=p['mods']+[{'source':'key','dest':'cutoff','amount':amt},{'source':'env2','dest':'cutoff','amount':float(v[4])},{'source':'env3','dest':'cutoff','amount':float(v[5])}]+([{'source':'key','dest':'amp','amount':a}] if abs(a)>0.01 else [])
if NEQ:p['effects']=eqs(pe)+list(p.get('effects',[]))
json.dump(p,open(BASE+'_pre.json','w'))
subprocess.run([PY,T+'/finalize.py',D,str(TR),BASE+'_pre.json',OUT],check=True)
print(subprocess.run([PY,T+'/lite.py',OUT,'/dev/null',str(C)],capture_output=True,text=True).stdout.strip())
