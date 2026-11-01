"""python add_bursts.py <export dir> <transpose> patch.json out.json t1,t2,... (ms) [levels]
Add bursts of noise at the measured times (bursts.py) to a resynth patch: a noise oscillator gated by a
square LFO1 whose rate the amp envelope pulls down through the note. The amp envelope decays to SUS, so
the table frames are scaled up by its inverse at their times and the level stays the recording's."""
import sys,json,copy;sys.path.insert(0,__file__.rsplit('/',1)[0])
from fitlib import *
from scipy.optimize import minimize
D,TR,P,OUT=sys.argv[1],float(sys.argv[2]),json.load(open(sys.argv[3])),sys.argv[4]
bt=np.array([float(v)/1000 for v in sys.argv[5].split(',')]);SUS=0.5
def burst_times(base,push,tau,T=1.0):
    t=np.arange(0,T,1e-4);r=base*2**(push*(SUS+(1-SUS)*np.exp(-t/tau)));ph=np.cumsum(r)*1e-4
    return np.array([t[np.searchsorted(ph,k)] for k in range(int(ph[-1])+1)])
def err(v):
    base,push,tau=np.exp(v[0]),v[1],np.exp(v[2]);bt2=burst_times(base,push,tau)
    if len(bt2)<len(bt):return 1e3+len(bt)-len(bt2)
    return float(np.sum((bt2[:len(bt)]-bt)**2)*1e6+(len(bt2)>len(bt))*np.sum(bt2[len(bt):]<0.97)*100)
best=min((minimize(err,[np.log(b),p,np.log(t)],method='Nelder-Mead',options={'maxiter':3000}) for b in (0.2,0.5,1) for p in (4,6,8) for t in (0.3,0.9)),key=lambda r:r.fun)
base,push,tau=np.exp(best.x[0]),best.x[1],np.exp(best.x[2])
print('LFO %.3f Hz, push %.2f oct, decay %.3f s -> bursts at %s ms'%(base,push,tau,np.round(burst_times(base,push,tau)*1000).astype(int)))
def build(level):
    q=copy.deepcopy(P);env=lambda t:SUS+(1-SUS)*np.exp(-t/tau)
    # Frame i's time from the position curve (resynth.py: W(1-exp(-t/TAU)) + (1-W) t/T, W .5, TAU .08, T 1).
    tg=np.linspace(0,1,20001);pg=0.5*(1-np.exp(-tg/0.08))+0.5*tg
    for o in q['oscillators']:
        for z in o['table']['zones']:
            n=len(z['frames'])
            for i,f in enumerate(z['frames']):
                g=1/env(min(float(np.interp(i/(n-1),pg,tg)),0.97));f['harmonics']=[float('%.4g'%(h*g)) for h in f['harmonics']]
    q['amp_env']=dict(q['amp_env'],decay_s=tau,sustain=SUS,curve='exp')
    q['oscillators'].append({'shape':'noise','level':level,'filtered':False})
    k=len(q['oscillators']);q['lfo1']={'shape':'square','rate_hz':base,'width':0.06}
    q['mods']=q['mods']+[{'source':'lfo1','dest':'osc%d.level'%k,'amount':level},{'source':'env1','dest':'lfo1.rate','amount':push}]
    return q
levels=[float(v) for v in sys.argv[6].split(',')] if len(sys.argv)>6 else [0.0,0.03,0.06,0.12,0.25]
x,notes=load_export(D);slots,rn,LEN=layout(probe_events(notes),notes=notes);HA=hfeats(x,slots,False,TR)
qs=[build(l) for l in levels];ys=render(qs,rn,LEN,'b',os.path.dirname(os.path.abspath(OUT)))
sc=[hloss(HA,hfeats(y,slots,True,TR))[0] for y in ys];i=int(np.argmin(sc))
print('levels',levels,'scores',['%.2f'%v for v in sc],'-> %.2f'%levels[i]);json.dump(qs[i],open(OUT,'w'))
