const { Cell } = require('@ton/core');
const hex='b5ee9c720101020100b20001e1800461dd9defe9c60589b7a718803c216a12cca22e1fb2acbe7763823de7a76408d0014c148f923891966b75af120e9a8dba3dc7f3234aa925b4141f9ba184448a2512004047cd11228d6bd1231641f83f3da1437b899843cdd4d7c91e0e866257369f8239c6bf5263400000000000004001007780003585903a83a6d17fd8d43781489ca36dd5c96de17a377df62722faec3ad4664d3debba000000002004f1a00000200240e0650e124ef1c7000250';
const c=Cell.fromBoc(Buffer.from(hex,'hex'))[0];
const s=c.beginParse();
s.loadAddress(); s.loadAddress(); s.loadAddress(); s.loadUintBig(32); s.loadUintBig(64);
const rs=s.loadRef().beginParse();
console.log('bits',rs.remainingBits);
for (let i=0;i<3;i++) {
 try { console.log('addr',i,rs.loadAddress().toRawString()); } catch(e){ console.log('addr err',i,e.message); break; }
}
console.log('rem bits',rs.remainingBits);
while(rs.remainingBits>=32){
  console.log('u32', rs.loadUintBig(32).toString(), 'hex', '0x'+rs.preloadUintBig? '': '');
}
