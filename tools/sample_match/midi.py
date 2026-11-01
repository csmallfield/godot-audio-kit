import sys,struct
def vlq(d,i):
    v=0
    while True:
        b=d[i];i+=1;v=(v<<7)|(b&127)
        if b<128:return v,i
def parse(p):
    d=open(p,'rb').read()
    fmt,ntr,div=struct.unpack('>HHH',d[8:14]);i=14;out=[];tempo=None
    for _ in range(ntr):
        assert d[i:i+4]==b'MTrk';ln=struct.unpack('>I',d[i+4:i+8])[0];j=i+8;end=j+ln;t=0;rs=0;on={}
        while j<end:
            dt,j=vlq(d,j);t+=dt;st=d[j]
            if st==0xFF:
                ty=d[j+1];l,k=vlq(d,j+2)
                if ty==0x51:tempo=int.from_bytes(d[k:k+3],'big')
                j=k+l;continue
            if st in(0xF0,0xF7):
                l,k=vlq(d,j+1);j=k+l;continue
            if st&0x80:rs=st;j+=1
            hi=rs&0xF0
            if hi in(0x80,0x90,0xA0,0xB0,0xE0):a,b=d[j],d[j+1];j+=2
            else:a=d[j];b=0;j+=1
            if hi==0x90 and b>0:on[a]=(t,b)
            elif hi==0x80 or(hi==0x90 and b==0):
                if a in on:s,v=on.pop(a);out.append((s/div,(t-s)/div,a,v))
            elif hi==0xB0:out.append((t/div,0,'cc%d'%a,b))
        i=end
    return div,tempo,sorted(out,key=lambda x:x[0])
if __name__=="__main__":
 for p in sys.argv[1:]:
    div,tempo,ev=parse(p);print(p.split('/')[-1],'div',div,'tempo',tempo,len(ev),'events')
    for e in ev:print('  beat %.2f len %.2f note %s vel %s'%e)
