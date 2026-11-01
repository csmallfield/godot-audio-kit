"""python floor.py <export dir> <transpose>: the original against itself (scene 3's two identical passes):
the lowest score a perfect copy could get, since detuned voices and free-running phases never repeat."""
import sys;sys.path.insert(0,__file__.rsplit('/',1)[0])
from fitlib import *
x,notes=load_export(sys.argv[1]);TR=float(sys.argv[2])
ts=sorted(set(n['t'] for n in notes));evs=[n for n in notes if 64<=n['t']<80 and n['len']>=0.2]
def slot(e,sh):
    nxt=min([t for t in ts if t>e['t']+1e-3]+[96.3]);return (e['t']+sh,e['t']+sh,min(e['len']+0.9,nxt-e['t']-0.005),e)
A=hfeats(x,[slot(e,0) for e in evs],False,TR);B=hfeats(x,[slot(e,16) for e in evs],False,TR)
print('%s floor %.1f dB'%(sys.argv[1].rstrip('/').rsplit('/',1)[-1],hloss(A,B)[0]))
