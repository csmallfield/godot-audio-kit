"""python curves.py full.json transpose [center]: can a full patch's key zones be explained by its center zone
plus a curve? Fits, by least squares on the zones' harmonic levels (dB), how much of the zone-to-zone
difference a few kinds of curve explain:
  level     a level per key
  eq        a level per key + one EQ curve fixed in Hz (what a static EQ after the voice does)
  eq(t)     the same, but the EQ curve changes through the note (a filter with an envelope)
  harm      a level per key + a curve over harmonic number per key octave (tilt in harmonic terms)
and prints the mean error (dB, weighted toward low harmonics, 60 dB floor) by distance from the center."""
import sys,json,numpy as np
from scipy.sparse import lil_matrix
from scipy.sparse.linalg import lsqr
p=json.load(open(sys.argv[1]));TR=float(sys.argv[2]);C=int(sys.argv[3]) if len(sys.argv)>3 else 72
o=next(o for o in p['oscillators'] if o.get('shape')=='table');Z=o['table']['zones'];cents=o.get('cents',0)
keys=[z['key'] for z in Z];F=len(Z[0]['frames']);c=min(range(len(keys)),key=lambda i:abs(keys[i]-C))
f0=lambda k:440*2**((k+TR+cents/100-69)/12)
def db(z,f):
    h=np.array(Z[z]['frames'][min(f,len(Z[z]['frames'])-1)]['harmonics']);return 20*np.log10(np.maximum(h,1e-9))
top=max(db(z,f).max() for z in range(len(Z)) for f in range(F));FL=top-60
# Data: per zone (not the center), frame and harmonic up to 40 / 12 kHz: target A[z]-A[c] where either is above the floor.
rows=[]
for z in range(len(Z)):
    if z==c:continue
    for f in range(F):
        a=db(z,f);b=db(c,f);K=int(min(40,12000//f0(keys[z]),len(a)))
        for k in range(1,K+1):
            av=max(a[k-1],FL);bv=max(b[k-1],FL) if k<=len(b) else FL
            if av>FL+1 or bv>FL+1:rows.append((z,f,k,av-bv,1/np.sqrt(k)))
R=np.array(rows);zi=R[:,0].astype(int);fi=R[:,1].astype(int);ki=R[:,2].astype(int);y=R[:,3];w=R[:,4]
KN=np.log2(np.geomspace(20,20000,31))   # EQ knots, a third of an octave apart
def hat(x,kn):
    """Linear-interpolation weights of x over the knots: (index, weight) pairs."""
    x=np.clip(x,kn[0],kn[-1]);i=np.clip(np.searchsorted(kn,x)-1,0,len(kn)-2);t=(x-kn[i])/(kn[i+1]-kn[i]);return [(i,1-t),(i+1,t)]
def fit(kind):
    nz=len(Z);cols={'level':nz,'eq':nz+len(KN),'eq(t)':nz+F*len(KN),'harm':nz+len(KN)*0+nz*8}[kind];A=lil_matrix((len(y),cols))
    for r in range(len(y)):
        z,f,k=zi[r],fi[r],ki[r];A[r,z]=w[r]
        if kind in('eq','eq(t)'):
            off=nz+(f*len(KN) if kind=='eq(t)' else 0)
            for i,t in hat(np.log2(k*f0(keys[z])),KN):A[r,off+i]+=w[r]*t
            for i,t in hat(np.log2(k*f0(keys[c])),KN):A[r,off+i]-=w[r]*t
        if kind=='harm':
            for i,t in hat(np.log2(k),np.arange(8.0)):A[r,nz+z*8+i]+=w[r]*t
    sol=lsqr(A.tocsr(),y*w,damp=0.05)[0];return np.abs(A.tocsr()@sol/w-y),sol
dist=np.abs(np.array(keys)[zi]-keys[c]);G=[(0,4),(4,13),(13,25),(25,60)]
def show(name,err):
    print('%-6s all %5.1f   '%(name,np.average(err,weights=w))+'  '.join('±%d-%d %5.1f'%(a,b-1,np.average(err[(dist>=a)&(dist<b)],weights=w[(dist>=a)&(dist<b)])) if ((dist>=a)&(dist<b)).any() else '' for a,b in G))
show('none',np.abs(y))
for kind in ['level','eq','eq(t)','harm']:
    e,sol=fit(kind);show(kind,e)
    if kind=='eq':np.save(sys.argv[1][:-5]+'_eq.npy',sol)
