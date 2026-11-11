"""Read-only PE/RTTI inventory for the S4 material-interface experiment."""
import argparse
import hashlib
import json
from pathlib import Path
import struct


def inspect(path):
    data=path.read_bytes()
    pe=struct.unpack_from("<I",data,60)[0]
    if data[:2]!=b"MZ" or data[pe:pe+4]!=b"PE\0\0":
        raise ValueError("expected PE image")
    count=struct.unpack_from("<H",data,pe+6)[0]
    optional=struct.unpack_from("<H",data,pe+20)[0]
    image=struct.unpack_from("<Q",data,pe+48)[0]
    sections=[]
    for i in range(count):
        offset=pe+24+optional+i*40
        size,va,raw_size,pointer=struct.unpack_from("<IIII",data,offset+8)
        sections.append((pointer,raw_size,va,size))

    def rva(offset):
        for pointer,raw_size,va,_ in sections:
            if pointer<=offset<pointer+raw_size:
                return offset-pointer+va
        raise ValueError("file offset outside sections")

    def file_offset(address):
        for pointer,raw_size,va,_ in sections:
            if va<=address<va+raw_size:
                return address-va+pointer
        raise ValueError("RVA outside file-backed sections")

    result={"path":str(path),"bytes":len(data),"sha256":hashlib.sha256(data).hexdigest(),
            "image_base":hex(image),"classes":{}}
    for name,slots in [("CMaterialSystem",[102,115,124]),
                       ("CMatQueuedRenderContext",[8,145,147,227]),
                       ("CMatRenderContext",[8,145])]:
        offset=data.find((".?AV"+name+"@@").encode())
        if offset<0:
            continue
        descriptor=rva(offset)-16
        matches=[]
        for offset in range(0,len(data)-24,4):
            signature,subobject,_,type_rva,_,_=struct.unpack_from("<IIIIII",data,offset)
            if signature!=1 or type_rva!=descriptor or subobject!=0:
                continue
            locator=rva(offset)
            needle=struct.pack("<Q",image+locator)
            start=0
            while (found:=data.find(needle,start))>=0:
                table=rva(found)+8
                methods={}
                for slot in slots:
                    target=struct.unpack_from("<Q",data,file_offset(table)+slot*8)[0]-image
                    methods[str(slot)]={"rva":hex(target),"prefix":data[file_offset(target):file_offset(target)+16].hex()}
                matches.append({"complete_object_locator":hex(locator),"vtable":hex(table),"methods":methods})
                start=found+1
        result["classes"][name]=matches
    return result


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image",type=Path)
    parser.add_argument("--out",type=Path,required=True)
    args=parser.parse_args()
    result=inspect(args.image)
    args.out.parent.mkdir(parents=True,exist_ok=True)
    args.out.write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8")
    print(result["sha256"])
