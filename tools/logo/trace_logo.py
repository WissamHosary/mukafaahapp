# Traces packages/mk_ui/assets/brand/logo_full.png into smooth shapes for the app intro.
# Writes packages/mk_ui/lib/src/intro_logo_data.dart. Run: python3 tools/logo/trace_logo.py (needs opencv-python, scipy, pillow).
# Run it from the repository root.
import cv2, numpy as np, json
from PIL import Image
from scipy.ndimage import gaussian_filter1d
im = np.array(Image.open('packages/mk_ui/assets/brand/logo_full.png').convert('RGBA')).astype(np.float32)
a = im[...,3]/255
r,g,b = im[...,0],im[...,1],im[...,2]
yellow = ((r>150)&(g>120)&(b<120)).astype(np.float32)*a
purple = ((r<140)&(b>20)&(g<100)).astype(np.float32)*a
K=6
def trace(mask, eps=0.15):
    big = cv2.resize(mask, None, fx=K, fy=K, interpolation=cv2.INTER_CUBIC)
    big = cv2.GaussianBlur(big,(0,0),0.6*K)
    bw = (big>0.5).astype(np.uint8)
    cs, hier = cv2.findContours(bw, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
    shapes={}  # outer index -> list of contours
    keep={}
    for i,c in enumerate(cs):
        if cv2.contourArea(c) < 30*K*K: continue
        pts = c[:,0,:].astype(np.float64)
        sg=1.6*K
        pts=np.stack([gaussian_filter1d(pts[:,0],sg,mode='wrap'),gaussian_filter1d(pts[:,1],sg,mode='wrap')],1)
        p=cv2.approxPolyDP(pts.astype(np.float32).reshape(-1,1,2),eps*K,True)[:,0,:]/K
        keep[i]=[[round(float(x),1),round(float(y),1)] for x,y in p]
    out=[]
    for i,c in keep.items():
        if hier[0][i][3]==-1:
            holes=[keep[j] for j in keep if hier[0][j][3]==i]
            pa=np.array(c); 
            out.append({'area':float(cv2.contourArea(np.array(c,np.float32))),'bbox':pa.min(0).tolist()+pa.max(0).tolist(),'paths':[c]+holes})
    return out
gap=535
ar=purple.copy(); ar[gap:]=0
en=purple.copy(); en[:gap]=0
mark=trace(yellow); arS=trace(ar); enS=trace(en)
# rotate mark start to the hook tip
c=mark[0]['paths'][0]; P=np.array(c); k=int(np.argmin(((P-[237,150])**2).sum(1))); mark[0]['paths'][0]=c[k:]+c[:k]
for s in arS: print('ar',round(s['area']),[round(v) for v in s['bbox']],len(s['paths']))
for s in enS: print('en',round(s['area']),[round(v) for v in s['bbox']],len(s['paths']))
print('mark start', mark[0]['paths'][0][0])
json.dump({'mark':mark,'ar':arS,'en':enS},open('/tmp/shapes.json','w'))

# ---- write Dart ----
d=json.load(open('/tmp/shapes.json'))
def shape(s):
    paths=',\n      '.join('['+', '.join(f'{x:g}, {y:g}' for x,y in p)+']' for p in s['paths'])
    b=', '.join(f'{v:g}' for v in s['bbox'])
    return f"  _Shape([\n      {paths},\n    ], [{b}]),"
ar_body=[s for s in d['ar'] if s['area']>=2000]
ar_dots=sorted([s for s in d['ar'] if s['area']<2000], key=lambda s:-s['bbox'][0])  # right to left
en=sorted(d['en'], key=lambda s:s['bbox'][0])
out=['// GENERATED from packages/mk_ui/assets/brand/logo_full.png by tools/logo/trace_logo.py.',
'// Do not edit by hand. Coordinates are in a 600 x 606 box, the size of the logo artwork.',
'// ignore_for_file: lines_longer_than_80_chars',
'',
"part of 'intro.dart';",
'',
'/// The yellow mark.',
'const _mark = [', shape(d['mark'][0]), '];',
'',
'/// The Arabic name without its dots and hamza.',
'const _arabicBody = [', *map(shape, ar_body), '];',
'',
'/// The dots and the hamza of the Arabic name, right to left.',
'const _arabicDots = [', *map(shape, ar_dots), '];',
'',
'/// MUKAFAAH, left to right.',
'const _latin = [', *map(shape, en), '];','']
open('packages/mk_ui/lib/src/intro_logo_data.dart','w').write('\n'.join(out))
json.dump({'mark':d['mark'][0],'arBody':ar_body,'arDots':ar_dots,'en':en},open('/tmp/preview_data.json','w'))
print(len(ar_body),len(ar_dots),len(en))
