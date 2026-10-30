# Vanilla .tiles (tdef v1) -> JSON {tileset: [props per tile]}.
#   python dump_tiledefs.py E:/pz-srv/media/newtiledefinitions.tiles out.json
import struct,sys,json
def rd(path):
    b=open(path,'rb').read(); p=0
    def i32():
        nonlocal p; v=struct.unpack_from('<i',b,p)[0]; p+=4; return v
    def line():
        nonlocal p; e=b.index(b'\n',p); s=b[p:e].decode('latin1'); p=e+1; return s
    assert b[:4]==b'tdef'; p=4; ver=i32(); n=i32(); out={}
    for _ in range(n):
        name=line(); img=line(); c=i32(); r=i32(); num=i32(); cnt=i32()
        tiles=[]
        for k in range(cnt):
            pc=i32(); props={}
            for _ in range(pc):
                kk=line(); vv=line(); props[kk]=vv
            tiles.append(props)
        out[name]=tiles
    return out
d=rd(sys.argv[1])
json.dump(d,open(sys.argv[2],'w'))
print(len(d))
