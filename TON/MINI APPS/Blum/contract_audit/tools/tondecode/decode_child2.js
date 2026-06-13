const { Cell } = require('@ton/core');
const samples = {
  child1: 'b5ee9c720101020100b20001e1800461dd9defe9c60589b7a718803c216a12cca22e1fb2acbe7763823de7a76408d0014c148f923891966b75af120e9a8dba3dc7f3234aa925b4141f9ba184448a2512004047cd11228d6bd1231641f83f3da1437b899843cdd4d7c91e0e866257369f8239c6bf5263400000000000004001007780003585903a83a6d17fd8d43781489ca36dd5c96de17a377df62722faec3ad4664d3debba000000002004f1a00000200240e0650e124ef1c7000250',
  child2: 'b5ee9c720101020100b10001e1800461dd9defe9c60589b7a718803c216a12cca22e1fb2acbe7763823de7a76408d00177a58c726b0cc24f4b14c180e927d16b7c9a7b2a4e101093174e673dee0fd726004047cd11228d6bd1231641f83f3da1437b899843cdd4d7c91e0e866257369f82382aa1efb94e000000000000400100758010fa533e5f48dc08220980e88bd47c0061262ba45a6a432ec7ff2fc802ad24620d3debba000000002004f1a00000200240c97951b766aaa00250'
};
for (const [k,v] of Object.entries(samples)) {
  const c = Cell.fromBoc(Buffer.from(v,'hex'))[0];
  const s = c.beginParse();
  console.log('===', k);
  console.log('root', s.loadAddress().toRawString());
  console.log('beneficiary', s.loadAddress().toRawString());
  console.log('jetton', s.loadAddress().toRawString());
  console.log('u32?', s.loadUintBig(32).toString());
  console.log('u64?', s.loadUintBig(64).toString());
  console.log('rem bits before ref', s.remainingBits, 'refs', s.remainingRefs);
  if (s.remainingRefs > 0) {
    const r = s.loadRef();
    const rs = r.beginParse();
    console.log('ref bits', rs.remainingBits, 'refs', rs.remainingRefs);
    const nums = [];
    while (rs.remainingBits >= 32 && nums.length < 8) {
      nums.push(rs.loadUintBig(Math.min(64, rs.remainingBits)).toString());
      if (rs.remainingBits === 0) break;
    }
    console.log('ref raw nums', nums);
  }
}
