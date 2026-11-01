"""python render_full.py <export dir> patch.json out.wav: render the export's whole MIDI through a patch."""
import sys,json,subprocess;sys.path.insert(0,__file__.rsplit('/',1)[0])
from fitlib import *
x,notes=load_export(sys.argv[1]);out=sys.argv[3];jn=out+'.notes.json'
json.dump([dict(time_s=n['t'],note=n['note'],velocity=n['vel'],length_s=n['len']) for n in notes],open(jn,'w'))
r=subprocess.run([GD,'--headless','--path',REPO,'-s',TOOLS+'/render_patch.gd','--',jn,sys.argv[2],out],capture_output=True,text=True)
os.remove(jn);print(r.stderr[-500:] if r.returncode else 'wrote '+out)
