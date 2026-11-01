"""python finalize.py <export dir> <transpose> patch.json out.json: set gain_db so the patch plays at the
recording's level (energy over the probe notes)."""
import sys,json;sys.path.insert(0,__file__.rsplit('/',1)[0])
from fitlib import *
x,notes=load_export(sys.argv[1]);TR=float(sys.argv[2]);p=json.load(open(sys.argv[3]));p['gain_db']=0.0
slots,rn,LEN=layout(probe_events(notes),notes=notes);HA=hfeats(x,slots,False,TR)
y=render([p],rn,LEN,'f_'+os.path.basename(sys.argv[4])[:-5],os.path.dirname(os.path.abspath(sys.argv[4])))[0];l,off=hloss(HA,hfeats(y,slots,True,TR))
p['gain_db']=round(off,2);json.dump(p,open(sys.argv[4],'w'));print('%s gain %+.1f dB'%(sys.argv[4].rsplit('/',1)[-1],off))
