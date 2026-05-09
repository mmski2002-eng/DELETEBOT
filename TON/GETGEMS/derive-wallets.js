const { mnemonicToWalletKey } = require('./nft-contracts/node_modules/@ton/crypto');
const { WalletContractV4 } = require('./nft-contracts/node_modules/@ton/ton');

async function derive(mnemonic, label) {
  const words = mnemonic.trim().split(/\s+/);
  const key = await mnemonicToWalletKey(words);
  const wallet = WalletContractV4.create({ publicKey: key.publicKey, workchain: 0 });
  console.log(label + ':');
  console.log('  testnet: ' + wallet.address.toString({ urlSafe: true, bounceable: true, testOnly: true }));
  console.log('  mainnet: ' + wallet.address.toString({ urlSafe: true, bounceable: true, testOnly: false }));
  console.log('  raw:     ' + wallet.address.toRawString());
  console.log('');
}

(async () => {
  await derive('wave tilt cause mechanic coral deer together odor gravity glue slogan equip normal post vehicle more explain suffer shy clutch canvas profit worry piano', 'Wallet 1 (Deployer)');
  await derive('cannon grief add talk green capable chunk neck obtain friend doctor echo since sorry bicycle elegant crew spin spoon debate universe modify neutral insane', 'Wallet 2 (Attacker)');
})();