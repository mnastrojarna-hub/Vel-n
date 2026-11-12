old=['#9CA3AF','#86EFAC','#4ADE80','#22C55E','#14B8A6','#CD7F32','#C0C0C0','#FFD700','#E5E4E2','#7DD3FC','#38BDF8','#3B82F6','#6366F1','#8B5CF6','#A855F7','#D946EF','#EF4444','#D4AF37','#F1F5F9','#FFD700']
new=['#A3B8A8','#BDF6D1','#4ADE80','#00AC7F','#0AA2A4','#C2844A','#929496','#E5D376','#B9BEC6','#AEE9FF','#2CD1D4','#6EAFFF','#00A1C7','#5087D4','#117897','#165EEB','#D42020','#EDB42D','#F5F8FB','#FF8C1A']
def lum(h):
    h=h.lstrip('#'); r=[int(h[i:i+2],16)/255 for i in (0,2,4)]
    r=[c/12.92 if c<=0.03928 else ((c+0.055)/1.055)**2.4 for c in r]
    return 0.2126*r[0]+0.7152*r[1]+0.0722*r[2]
def cr(a,b):
    la,lb=lum(a),lum(b); return (max(la,lb)+0.05)/(min(la,lb)+0.05)
def on(h): return '#0F1A14' if lum(h)>0.5 else '#FFFFFF'
print('lv  old      onText  CR   onDark1A2E22 onDark0A1A10 | new      onText  CR(_onColor) best   onDark1A2E22 onDark0A1A10')
for i,(o,n) in enumerate(zip(old,new),1):
    bo=max(cr(n,'#0F1A14'),cr(n,'#FFFFFF'))
    print(f"{i:2d} {o} {on(o)} {cr(o,on(o)):4.2f} {cr(o,'#1A2E22'):5.2f} {cr(o,'#0A1A10'):5.2f} | {n} {on(n)} {cr(n,on(n)):4.2f} {bo:4.2f} {cr(n,'#1A2E22'):5.2f} {cr(n,'#0A1A10'):5.2f}")
