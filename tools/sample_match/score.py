"""python score.py <export dir> <transpose> patch.json [patch.json ...]: harmonic and band loss of each patch (gain solved)"""
import sys,json,time;sys.path.insert(0,__file__.rsplit('/',1)[0])
from fitlib import *
x,notes=load_export(sys.argv[1]);TR=float(sys.argv[2]);slots,rn,LEN=layout(probe_events(notes),notes=notes)
FA=feats(x,slots,False);HA=hfeats(x,slots,False,TR)
ps=[json.load(open(p)) for p in sys.argv[3:]]
for p,y in zip(sys.argv[3:],render(ps,rn,LEN,'s',os.path.dirname(os.path.abspath(sys.argv[3])))):
    t=time.time();h,ho=hloss(HA,hfeats(y,slots,True,TR));l,o=loss(FA,feats(y,slots,True))
    print('%-28s harmonic %.2f dB (gain %+.1f)  band %.2f dB  [%.1fs]'%(p.rsplit('/',1)[-1],h,ho,l,time.time()-t))
