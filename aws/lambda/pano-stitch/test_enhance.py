import sys; sys.path.insert(0,'.')
import cv2, numpy as np, enhance

def stub_edit(bgr, hole, region):
    # deterministic 'fill': continue with the mean of the non-hole border, no network
    out = bgr.copy()
    keep = hole == 0
    fill = bgr[keep].mean(axis=0) if keep.any() else np.array([128,128,128])
    out[hole>0] = fill.astype(np.uint8)
    return out

# synthetic room equirect: colored walls + bright ceiling + dark-ish floor
H,W = 1024,2048
eq = np.zeros((H,W,3),np.uint8)
xx = np.linspace(0,1,W)
for c in range(3):
    eq[:,:,c] = (128+120*np.sin(2*np.pi*xx + c)).astype(np.uint8)[None,:]
eq[:int(H*0.12)] = 210          # ceiling band
eq[int(H*0.88):] = 70           # floor band

# simulate a partial pano: blank an 80deg wedge straddling the wrap seam + black poles
ww = int(W*80/360); half=ww//2
part = eq.copy(); part[:,W-half:]=0; part[:,:ww-half]=0

before_missing = enhance._missing_columns(part).mean()*360
out = enhance.enhance(part, stub_edit)
after_missing = enhance._missing_columns(out).mean()*360

assert out.shape == eq.shape, out.shape
assert before_missing > 60, f'wedge not simulated: {before_missing:.0f}'
assert after_missing < 5, f'wrap NOT closed: {after_missing:.0f}deg still missing'
# wrap-seam continuity: cols W-1 and 0 should be close after closing
seam_gap = float(np.abs(out[:,0].astype(int)-out[:,-1].astype(int)).mean())
assert seam_gap < 25, f'seam discontinuous: {seam_gap:.1f}'
print(f'OK  wedge {before_missing:.0f}deg -> {after_missing:.0f}deg ; seam gap {seam_gap:.1f}/255 ; shape {out.shape}')
