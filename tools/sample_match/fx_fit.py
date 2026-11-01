"""python fx_fit.py <export dir> <transpose> patch.json out.json [gens]
Search effects on top of a resynth patch: a chorus and a reverb (each can stay off) and the release.
For sounds whose movement or tail comes from effects (a tempo-locked chorus, a reverb), which a table
taken from the wet recording can't make. Score: the harmonic score plus the left/right correlation gap."""
import sys,json,copy;sys.path.insert(0,__file__.rsplit('/',1)[0])
from fitlib import *
D,TR,BASE,OUT=sys.argv[1],float(sys.argv[2]),json.load(open(sys.argv[3])),sys.argv[4];GENS=int(sys.argv[5]) if len(sys.argv)>5 else 12
P={'cmix':(0,1),'crate':(0.1,6),'cdepth':(0.3,8),'cdelay':(4,25),'rmix':(0,0.7),'room':(0.2,0.97),'damp':(0,1),'rel':(0.3,3)}
LOG={'crate','cdepth','rel'}
def decode(p):
    q=copy.deepcopy(BASE);fx=[]
    if p['cmix']>0.02:fx.append({'type':'chorus','mix':p['cmix'],'rate_hz':p['crate'],'depth_ms':p['cdepth'],'delay_ms':p['cdelay'],'voices':2})
    if p['rmix']>0.02:fx.append({'type':'reverb','room':p['room'],'damp':p['damp'],'mix':p['rmix']})
    q['effects']=fx;q['amp_env']=dict(q['amp_env'],release_s=BASE['amp_env']['release_s']*p['rel']);return q
x,notes=load_export(D);slots,rn,LEN=layout(probe_events(notes),notes=notes);HA=hfeats(x,slots,False,TR)
def corr(y):
    seg=np.concatenate([y[int(nt*SR):int((nt+d)*SR)] for ot,nt,d,e in slots]);l,r=seg.T
    return np.dot(l,r)/np.sqrt(np.dot(l,l)*np.dot(r,r)+1e-20)
lo,ro=np.concatenate([x[int(ot*SR):int((ot+d)*SR)] for ot,nt,d,e in slots]).T;C0=np.dot(lo,ro)/np.sqrt(np.dot(lo,lo)*np.dot(ro,ro))
def ev(ps,tag):
    ys=render([decode(p) for p in ps],rn,LEN,tag,os.path.dirname(os.path.abspath(OUT)))
    return [hloss(HA,hfeats(y,slots,True,TR))[0]+10*abs(corr(y)-C0) for y in ys]
rng=np.random.default_rng(3)
start={'cmix':0.0,'crate':0.8,'cdepth':3,'cdelay':12,'rmix':0.0,'room':0.6,'damp':0.5,'rel':1.0}
grid=[dict(start,cmix=c,rmix=r,room=rm) for c in (0,0.3,0.6) for r in (0,0.2,0.4) for rm in (0.5,0.85)][:23]
sc=ev(grid,'g');i=int(np.argmin(sc));best,bl=grid[i],sc[i];print('grid %.2f'%bl,best,flush=True);step=1.0
for g in range(GENS):
    kids=[]
    for _ in range(23):
        q=dict(best)
        for k in rng.choice(list(P),size=rng.integers(1,4),replace=False):
            lo_,hi_=P[k];q[k]=float(np.clip(q[k]*np.exp(rng.normal()*step) if k in LOG else q[k]+rng.normal()*step*(hi_-lo_)*0.25,lo_,hi_))
        kids.append(q)
    sc=ev(kids,'e');i=int(np.argmin(sc))
    if sc[i]<bl:best,bl=kids[i],sc[i];step=min(step*1.1,1.5)
    else:step*=0.8
    print('gen %d %.2f'%(g,bl),flush=True)
json.dump(decode(best),open(OUT,'w'));print('best %.2f'%bl,json.dumps(best))
