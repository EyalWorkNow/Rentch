import numpy as np, cv2, sys
sys.path.insert(0, '.')
import cube_ops as C
H, W = 512, 1024
yy, xx = np.meshgrid(np.arange(H), np.arange(W), indexing='ij')
lon = (xx+0.5)/W*360 - 180
lat = 90 - (yy+0.5)/H*180
# color encodes lon (R), lat (G), and a fine checker (B) to catch flips/rotations
img = np.zeros((H,W,3), np.uint8)
img[...,2] = ((lon+180)/360*255).astype(np.uint8)      # R
img[...,1] = ((lat+90)/180*255).astype(np.uint8)       # G
img[...,0] = (((xx//32 + yy//32) % 2)*255).astype(np.uint8)  # B checker
faces = C.e2c(img, 256)
recon = C.c2e(faces, H, W)
band = slice(int(H*0.28), int(H*0.72))  # equatorial band (poles resample hard)
err = np.abs(img[band].astype(int) - recon[band].astype(int)).mean()
errfull = np.abs(img.astype(int) - recon.astype(int)).mean()
print(f'faces: {list(faces.keys())}, face shape {faces["F"].shape}')
print(f'mean abs err  band={err:.2f}  full={errfull:.2f}  (0-255 scale)')
print('BAND PASS' if err < 6 else 'BAND FAIL')
