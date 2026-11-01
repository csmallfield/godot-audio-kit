"""python slots.py <export dir> <transpose> patch.json [patch.json]: harmonic loss per probe note, side by side"""
import sys,json;sys.path.insert(0,__file__.rsplit('/',1)[0])
from fitlib import *
x,notes=load_export(sys.argv[1]);TR=float(sys.argv[2]);slots,rn,LEN=layout(probe_events(notes),notes=notes);HA=hfeats(x,slots,False,TR)
ps=sys.argv[3:];ys=render([json.load(open(p)) for p in ps],rn,LEN,'s',os.path.dirname(os.path.abspath(ps[0])))
H=[hfeats(y,slots,True,TR) for y in ys];offs=[hloss(HA,h)[1] for h in H]
print('note  t      len  vel  '+'  '.join('%-10s'%p.rsplit('/',1)[-1][:10] for p in ps)+'  (level dB vs original)')
for i,(ot,nt,dur,e) in enumerate(slots):
    row=[]
    for h,o in zip(H,offs):
        l,_=hloss([HA[i]],[h[i]]);
        lv=10*np.log10(np.sum(10**(h[i][0]/10))*10**(o/10)/np.sum(10**(HA[i][0]/10)))
        row.append('%5.1f %+5.1f'%(l,lv))
    print('%3d %6.2f %5.2f %4.2f  '%(e['note'],ot,e['len'],e['vel'])+'  '.join(row))
