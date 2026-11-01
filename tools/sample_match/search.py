"""python search.py <export dir> <transpose> <out prefix> [gens] [seed json of params] [nogrid|grid] [frozen,keys]"""
import sys,json,time,numpy as np
sys.path.insert(0,__file__.rsplit('/',1)[0])
from fitlib import *
D,TR,OUT=sys.argv[1],float(sys.argv[2]),sys.argv[3];GENS=int(sys.argv[4]) if len(sys.argv)>4 else 20
S=os.path.dirname(OUT)
SHAPES=['saw','square','triangle','sine','pulse']
# name: (lo, hi, kind)  kind: lin | log | int | cat:<n>
P={'sh1':(0,4.99,'cat'),'sh2':(0,4.99,'cat'),'semi2':(0,5.99,'cat'),'lvl2':(0,1,'lin'),'cents2':(-50,50,'lin'),'width':(0.05,0.5,'lin'),
   'uni':(1,5.99,'int'),'det':(0,60,'lin'),'cut':(30,16000,'log'),'res':(0,0.9,'lin'),'kt':(0,1,'lin'),
   'fenv':(0,9,'lin'),'fdec':(0.02,3,'log'),'fsus':(0,1,'lin'),'fvel':(0,4,'lin'),
   'vcurve':(0.5,3,'lin'),'ulvl':(0,1,'lin'),'spread':(0,1,'lin'),'pan2':(-1,1,'lin'),'mono':(0,1.99,'cat'),'glide':(0,0.3,'lin'),
   'vib':(0,1,'lin'),'vrate':(2,9,'lin'),'trem':(0,0.8,'lin'),'trate':(1,9,'lin'),'rvb':(0,0.6,'lin'),'room':(0.2,0.95,'lin'),'cho':(0,1,'lin'),
   'bst':(0,0.6,'lin'),'bw':(0.03,0.5,'lin'),'brate':(0.1,4,'log'),'bpush':(0,7,'lin'),'bdec':(0.1,3,'log'),
   'penv':(-2,2,'lin'),'pdec':(0.01,1,'log'),
   'pha':(0,1,'lin'),'prate':(0.1,8,'log'),'pfb':(0,0.9,'lin'),'fla':(0,1,'lin'),'frate':(0.05,5,'log'),'ffb':(-0.9,0.9,'lin'),
   'att':(0.001,0.4,'log'),'dec':(0.01,3,'log'),'sus':(0,1,'lin'),'rel':(0.002,3,'log'),'vsens':(0,1,'lin'),'noise':(0,0.5,'lin')}
SEMI2=[0,12,-12,24,7,19]
FROZEN=set(sys.argv[7].split(',')) if len(sys.argv)>7 else set()
def clip(k,v):lo,hi,_=P[k];return min(max(v,lo),hi)
def decode(p,gain=0.0):
    o1={'shape':SHAPES[int(p['sh1'])],'level':0.7,'semitones':TR,'width':p['width']}
    o2={'shape':SHAPES[int(p['sh2'])],'level':0.7*p['lvl2'],'semitones':TR+SEMI2[int(p['semi2'])],'cents':p['cents2'],'width':p['width'],'pan':p['pan2']}
    osc=[o1,o2]
    if p['noise']>0.01:osc.append({'shape':'noise','level':0.7*p['noise']})
    mods=[{'source':'env2','dest':'cutoff','amount':p['fenv']},{'source':'velocity','dest':'cutoff','amount':p['fvel']}]
    if p['kt']>0.01:mods.append({'source':'key','dest':'cutoff','amount':p['kt']})
    burst=p['bst']>0.005
    if burst:
        # Noise around the filter, gated by a square LFO1 that env3 slows down.
        osc.append({'shape':'noise','level':p['bst'],'filtered':False})
        mods+=[{'source':'lfo1','dest':'osc%d.level'%len(osc),'amount':p['bst']},{'source':'env3','dest':'lfo1.rate','amount':p['bpush']}]
    elif p['vib']>0.005:mods.append({'source':'lfo1','dest':'pitch','amount':p['vib']})
    if not burst and abs(p['penv'])>0.01:mods.append({'source':'env3','dest':'pitch','amount':p['penv']})
    if p['trem']>0.005:mods.append({'source':'lfo2','dest':'amp','amount':-p['trem']})
    fx=[]
    if p['cho']>0.01:fx.append({'type':'chorus','mix':p['cho']*0.5,'depth_ms':3.0,'delay_ms':12.0,'voices':2})
    if p['pha']>0.01:fx.append({'type':'phaser','rate_hz':p['prate'],'feedback':p['pfb'],'mix':p['pha']})
    if p['fla']>0.01:fx.append({'type':'flanger','rate_hz':p['frate'],'feedback':p['ffb'],'mix':p['fla']})
    if p['rvb']>0.01:fx.append({'type':'reverb','room':p['room'],'mix':p['rvb']})
    return {'oscillators':osc,'unison':int(p['uni']),'detune_cents':p['det'],
     'filter':{'type':'ladder','cutoff_hz':p['cut'],'resonance':p['res'],'drive':1.0},
     'amp_env':{'attack_s':p['att'],'decay_s':p['dec'],'sustain':p['sus'],'release_s':p['rel'],'curve':'exp'},
     'env2':{'attack_s':0.0,'decay_s':p['fdec'],'sustain':p['fsus'],'release_s':max(p['rel'],0.01),'curve':'exp'},
     'mods':mods,'velocity_sens':p['vsens'],'velocity_curve':p['vcurve'],'unison_level':p['ulvl'],'spread':p['spread'],
     'mode':['poly','mono'][int(p['mono'])],'glide_s':p['glide'],'polyphony':16,'gain_db':gain,
     'lfo1':({'shape':'square','rate_hz':p['brate'],'width':p['bw']} if burst else {'shape':'sine','rate_hz':p['vrate']}),
     'env3':{'attack_s':0.0,'decay_s':p['bdec'] if burst else p['pdec'],'sustain':0.0,'release_s':0.2,'curve':'exp'},'lfo2':{'shape':'sine','rate_hz':p['trate']},'effects':fx}
def mutate(p,rng,step):
    q=dict(p)
    for k in rng.choice([k for k in P if k not in FROZEN],size=rng.integers(1,4),replace=False):
        lo,hi,kind=P[k]
        if kind=='log':q[k]=clip(k,q[k]*np.exp(rng.normal()*step*1.5))
        elif kind=='cat':q[k]=float(rng.integers(0,int(hi)+1))
        elif kind=='int':q[k]=clip(k,q[k]+rng.choice([-1,1]))
        else:q[k]=clip(k,q[k]+rng.normal()*step*(hi-lo)*0.3)
        q[k]=float(q[k])
    return q
x,notes=load_export(D);slots,rn,LEN=layout(probe_events(notes),notes=notes)
FA=hfeats(x,slots,False,TR)
def evaluate(ps,tag):
    ys=render([decode(p) for p in ps],rn,LEN,tag,S);res=[]
    for y in ys:res.append(hloss(FA,hfeats(y,slots,True,TR)))
    return res
start={'sh1':0,'sh2':0,'semi2':1,'lvl2':0.0,'cents2':0,'width':0.3,'uni':1,'det':10,'cut':800,'res':0.1,'kt':0.5,'fenv':1,'fdec':0.3,'fsus':0.5,'fvel':0.5,
       'att':0.005,'dec':0.3,'sus':0.7,'rel':0.1,'vsens':0.5,'noise':0.0,'vcurve':1.0,'ulvl':1.0,'spread':0.0,'pan2':0.0,'mono':0,'glide':0.0,'vib':0.0,'vrate':5.0,'trem':0.0,'trate':5.0,'rvb':0.0,'room':0.6,'cho':0.0,'bst':0.0,'bw':0.12,'brate':0.36,'bpush':5.76,'bdec':0.92,'penv':0.0,'pdec':0.1,'pha':0.0,'prate':0.5,'pfb':0.4,'fla':0.0,'frate':0.3,'ffb':0.5}
if len(sys.argv)>5:start.update(json.load(open(sys.argv[5])))
rng=np.random.default_rng(1)
# stage 0: oscillator shapes and second-osc interval on a coarse grid
grid=[dict(start,sh1=a,sh2=b,semi2=c,lvl2=l) for a in [0,1,2] for b,c,l in [(0,1,0.0),(0,1,0.5),(1,1,0.5),(3,2,0.6),(0,2,0.5),(2,3,0.4),(0,0,0.7)]]
if len(sys.argv)>6 and sys.argv[6]=='nogrid':grid=[start]
t0=time.time();res=evaluate(grid,'g');i=int(np.argmin([r[0] for r in res]));best,bl=grid[i],res[i]
print('grid best %.2f dB (%.0fs)'%(bl[0],time.time()-t0),{k:best[k] for k in ['sh1','sh2','semi2','lvl2']},flush=True)
step=1.0
for g in range(GENS):
    kids=[mutate(best,rng,step) for _ in range(23)]
    res=evaluate(kids,'e');i=int(np.argmin([r[0] for r in res]))
    if res[i][0]<bl[0]:best,bl=kids[i],res[i];step=min(step*1.1,1.5)
    else:step*=0.8
    print('gen %2d loss %.2f step %.2f'%(g,bl[0],step),flush=True)
json.dump(best,open(OUT+'_params.json','w'),indent=1)
final=decode(best,gain=bl[1]);json.dump(final,open(OUT+'_patch.json','w'),indent=1)
print('final loss %.2f dB, gain %.1f dB'%(bl[0],bl[1]));print(json.dumps(best))
