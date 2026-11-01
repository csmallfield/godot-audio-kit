"""python score.py <export dir> patch.json [patch.json ...]: band loss of each patch (gain solved)"""
import sys,json;sys.path.insert(0,__file__.rsplit('/',1)[0])
from fitlib import *
x,notes=load_export(sys.argv[1]);slots,rn,LEN=layout(probe_events(notes));FA=feats(x,slots,False)
ps=[json.load(open(p)) for p in sys.argv[2:]]
for p,y in zip(sys.argv[2:],render(ps,rn,LEN,'s',os.path.dirname(os.path.abspath(sys.argv[2])))):
    l,o=loss(FA,feats(y,slots,True));print('%-40s loss %.2f dB  gain offset %+.1f'%(p.rsplit('/',1)[-1],l,o))
