/**
 * Sherlock Protocol Mainnet Query Script
 * Uses Node.js built-in https module (no ethers.js dependency)
 * Queries Ethereum mainnet via public RPC to find ProtocolManager address and protocol parameters
 */

const https = require('https');
const crypto = require('crypto');

const SHERLOCK_ADDRESS = '0x0865a889183039689034dA55c1Fd12aF5083eabF';
const RPC_URL = 'https://eth.llamarpc.com';

const ZERO = '0x0000000000000000000000000000000000000000000000000000000000000000';

function keccak256(msg) {
  return crypto.createHash('sha3-256').update(Buffer.from(msg, 'utf-8')).digest('hex');
}

function rpcCall(method, params) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify({
      jsonrpc: '2.0',
      method,
      params,
      id: 1
    });

    const url = new URL(RPC_URL);
    const options = {
      hostname: url.hostname,
      port: 443,
      path: url.pathname,
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) }
    };

    const req = https.request(options, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(body);
          if (parsed.error) reject(new Error(JSON.stringify(parsed.error)));
          else resolve(parsed.result);
        } catch (e) {
          reject(new Error('Parse error: ' + body));
        }
      });
    });

    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

function getSelector(sig) {
  return '0x' + keccak256(sig).slice(0, 8);
}

function encodeCall(sig, ...args) {
  const selector = getSelector(sig);
  let encoded = selector.slice(2); // Remove 0x
  for (const arg of args) {
    const clean = arg.startsWith('0x') ? arg.slice(2) : arg;
    encoded += clean.padStart(64, '0');
  }
  return '0x' + encoded;
}

function decodeUint(data) {
  if (!data || data === '0x') return '0';
  const hex = data.startsWith('0x') ? data.slice(2) : data;
  return BigInt('0x' + hex).toString();
}

function decodeAddress(data) {
  if (!data || data === '0x') return '0x0000000000000000000000000000000000000000';
  const hex = data.startsWith('0x') ? data.slice(2) : data;
  return '0x' + hex.slice(24, 64);
}

async function ethCall(to, sig, ...args) {
  const data = encodeCall(sig, ...args);
  const result = await rpcCall('eth_call', [{ to, data }, 'latest']);
  return result;
}

async function getBlockNumber() {
  return await rpcCall('eth_blockNumber', []);
}

async function getBlockByNumber(blockNum) {
  return await rpcCall('eth_getBlockByNumber', [blockNum, false]);
}

function parseBytes32String(hex) {
  if (!hex || hex === '0x' + '0'.repeat(64)) return '';
  const bytes = hex.startsWith('0x') ? hex.slice(2) : hex;
  let str = '';
  for (let i = 0; i < bytes.length; i += 2) {
    const code = parseInt(bytes.slice(i, i + 2), 16);
    if (code === 0) break;
    str += String.fromCharCode(code);
  }
  return str;
}

async function main() {
  console.log('='.repeat(80));
  console.log('SHERLOCK PROTOCOL - MAINNET ON-CHAIN QUERY');
  console.log('='.repeat(80));

  // Check connection
  const blockNumHex = await getBlockNumber();
  const blockNum = parseInt(blockNumHex, 16);
  console.log('✅ Connected! Block:', blockNum);

  // Step 1: Get Sherlock contract addresses
  console.log('\n📋 STEP 1: Sherlock Core Contract State');
  console.log('-'.repeat(50));

  const sherlockPM = await ethCall(SHERLOCK_ADDRESS, 'sherlockProtocolManager()');
  const yieldStrategy = await ethCall(SHERLOCK_ADDRESS, 'yieldStrategy()');
  const token = await ethCall(SHERLOCK_ADDRESS, 'token()');
  const sher = await ethCall(SHERLOCK_ADDRESS, 'sher()');

  const pmAddr = decodeAddress(sherlockPM);
  const yAddr = decodeAddress(yieldStrategy);
  const tAddr = decodeAddress(token);
  const sAddr = decodeAddress(sher);

  console.log(`Sherlock:              ${SHERLOCK_ADDRESS}`);
  console.log(`ProtocolManager:       ${pmAddr}`);
  console.log(`YieldStrategy:         ${yAddr}`);
  console.log(`Token (USDC):          ${tAddr}`);
  console.log(`SHER:                  ${sAddr}`);

  // Step 2: Get ProtocolManager global state
  console.log('\n📋 STEP 2: ProtocolManager Global State');
  console.log('-'.repeat(50));

  const claimablePremiumsResult = await ethCall(pmAddr, 'claimablePremiums()');
  const minActiveBalanceResult = await ethCall(pmAddr, 'minActiveBalance()');
  const allPremiumsPerSecResult = await ethCall(pmAddr, 'allPremiumsPerSecToStakers()');
  const lastAccountedGlobalResult = await ethCall(pmAddr, 'lastAccountedGlobal()');

  const claimablePremiums = BigInt(decodeUint(claimablePremiumsResult));
  const minActiveBalance = BigInt(decodeUint(minActiveBalanceResult));
  const allPremiumsPerSec = BigInt(decodeUint(allPremiumsPerSecResult));
  const lastAccountedGlobal = parseInt(decodeUint(lastAccountedGlobalResult));

  console.log(`claimablePremiums:         ${(claimablePremiums / 1000000n).toString()} USDC`);
  console.log(`minActiveBalance:          ${(minActiveBalance / 1000000n).toString()} USDC`);
  console.log(`allPremiumsPerSecToStakers: ${(allPremiumsPerSec / 1000000n).toString()} USDC/sec`);
  console.log(`lastAccountedGlobal:        ${new Date(lastAccountedGlobal * 1000).toISOString()}`);

  // Step 3: Check protocols
  console.log('\n📋 STEP 3: Checking Protocols');
  console.log('-'.repeat(50));

  // Sherlock v2 actually uses the protocol's address (bytes32 = address) 
  // or more commonly the keccak256 of the protocol address
  // Let me try actual Sherlock-covered protocol addresses
  
  // Protocols known to be covered by Sherlock (from their docs/history):
  // We need to check what bytes32 identifiers Sherlock uses
  // In Sherlock v2, protocol = keccak256(protocolAddress)
  // But let's try empty/numeric first
  
  // Try to find protocols via events would be ideal, but let's try direct storage reads
  // The ProtocolManager has protocolAgent_ mapping. In Solidity 0.8.10, mapping storage slot
  // is at slot for protocolAgent_. Let's try reading storage.
  
  // SherlockProtocolManager storage layout (after Manager.sol inheritance):
  // Manager.sol: 
  //   slot 0: _owner (Ownable)
  //   slot 1: _paused (Pausable)
  //   slot 2: sherlockCore (ISherlock)
  // ProtocolManager.sol:
  //   slot 3: token (immutable - not in storage)
  //   slot 4: protocolAgent_ (mapping)
  //   slot 5: nonStakersPercentage (mapping)
  //   slot 6: premiums_ (mapping)
  //   slot 7: activeBalances (mapping)
  //   slot 8: lastAccountedEachProtocol (mapping)
  //   slot 9: nonStakersClaimableByProtocol (mapping)
  //   slot 10: lastAccountedGlobal
  //   slot 11: allPremiumsPerSecToStakers
  //   slot 12: lastClaimablePremiumsForStakers
  //   slot 13: minActiveBalance
  //   slot 14: removedProtocolClaimDeadline (mapping)
  //   slot 15: removedProtocolAgent (mapping)
  //   slot 16: currentCoverage (mapping)
  //   slot 17: previousCoverage (mapping)

  // For mappings, slot = keccak256(key . slot)
  function getMappingSlot(key, baseSlot) {
    const keyPadded = key.startsWith('0x') ? key.slice(2).padStart(64, '0') : key.padStart(64, '0');
    const slotHex = BigInt(baseSlot).toString(16).padStart(64, '0');
    const concat = keyPadded + slotHex;
    // keccak256 of the concatenated bytes
    const hash = crypto.createHash('sha3-256').update(Buffer.from(concat, 'hex')).digest('hex');
    return '0x' + hash;
  }

  // Try to enumerate protocols by checking some known protocol addresses
  // as bytes32 identifiers
  const knownProtocolAddresses = [
    '0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9', // Aave V2 LendingPool
    '0xc0a47dFe034B400B47bDaD5FecDa2621de6c4d95', // Uniswap V2 Factory
    '0x1F98431c8aD98523631AE4a59f267346ea31F984', // Uniswap V3 Factory
    '0xbc4ca0eda7647a8ab7c2061c2e118a18a936f13d', // Aavegotchi
    '0xBA12222222228d8Ba445958a75a0704d566BF2C8', // Balancer Vault
  ];

  // Also try just using the address directly as bytes32 (left-padded)
  for (const protocolAddr of knownProtocolAddresses) {
    // Protocol bytes32 = left-padded address (bytes32)
    const pBytes = '0x' + '000000000000000000000000' + protocolAddr.slice(2).toLowerCase();
    
    try {
      const agentResult = await ethCall(pmAddr, 'protocolAgent(bytes32)', pBytes);
      const agent = decodeAddress(agentResult);

      if (agent && agent !== '0x0000000000000000000000000000000000000000') {
        console.log(`\n🔍 Protocol found: ${protocolAddr}`);
        console.log(`   Bytes32: ${pBytes}`);
        console.log(`   Agent:   ${agent}`);

        const premiumResult = await ethCall(pmAddr, 'premium(bytes32)', pBytes);
        const activeBalResult = await ethCall(pmAddr, 'activeBalance(bytes32)', pBytes);
        const secondsLeftResult = await ethCall(pmAddr, 'secondsOfCoverageLeft(bytes32)', pBytes);
        const lastAccResult = await ethCall(pmAddr, 'lastAccountedEachProtocol(bytes32)', pBytes);

        const premium = BigInt(decodeUint(premiumResult));
        const activeBal = BigInt(decodeUint(activeBalResult));
        const lastAcc = parseInt(decodeUint(lastAccResult));

        const currentBlockData = await getBlockByNumber('latest');
        const currentTimestamp = parseInt(currentBlockData.timestamp, 16);
        const timeDiff = currentTimestamp - lastAcc;
        const debt = premium * BigInt(timeDiff);

        console.log(`   Premium/sec: ${(premium / 1000000n).toString()} USDC`);
        console.log(`   Active Balance: ${(activeBal / 1000000n).toString()} USDC`);
        console.log(`   Last Accounted: ${new Date(lastAcc * 1000).toISOString()}`);
        console.log(`   Time since last accounting: ${timeDiff} sec`);
        console.log(`   Debt accrued: ${(debt / 1000000n).toString()} USDC`);
        console.log(`   Debt > Active Balance? ${debt > activeBal ? '⚠️ YES - VULNERABLE!' : '✅ No'}`);
      }
    } catch (e) {
      // Skip - protocol doesn't exist
    }
  }

  // Also try some known protocol bytes32 identifiers from Sherlock v1/v2
  // In Sherlock v2, protocols might use keccak256(protocolAddress) as identifier
  for (const protocolAddr of knownProtocolAddresses) {
    const addrClean = protocolAddr.toLowerCase();
    const hash = crypto.createHash('sha3-256').update(Buffer.from(addrClean, 'utf-8')).digest('hex');
    const pBytes = '0x' + hash;
    
    try {
      const agentResult = await ethCall(pmAddr, 'protocolAgent(bytes32)', pBytes);
      const agent = decodeAddress(agentResult);

      if (agent && agent !== '0x0000000000000000000000000000000000000000') {
        console.log(`\n🔍 Protocol (keccak): ${protocolAddr}`);
        console.log(`   Bytes32: ${pBytes}`);
        console.log(`   Agent:   ${agent}`);

        const premiumResult = await ethCall(pmAddr, 'premium(bytes32)', pBytes);
        const activeBalResult = await ethCall(pmAddr, 'activeBalance(bytes32)', pBytes);
        const premium = BigInt(decodeUint(premiumResult));
        const activeBal = BigInt(decodeUint(activeBalResult));

        console.log(`   Premium/sec: ${(premium / 1000000n).toString()} USDC`);
        console.log(`   Active Balance: ${(activeBal / 1000000n).toString()} USDC`);
      }
    } catch (e) {
      // Skip
    }
  }

  // Also check if there's a way to enumerate protocols
  // In Sherlock v1, there was a protocolCounter and a protocols mapping
  // Let's try reading the storage directly
  
  // Try storage slot 3 (minActiveBalance - first non-mapping, non-immutable variable)
  try {
    const slot3 = await rpcCall('eth_getStorageAt', [pmAddr, '0x03', 'latest']);
    console.log(`\n📋 Storage slot 3 (maybe minActiveBalance): ${slot3}`);
    
    const slot10 = await rpcCall('eth_getStorageAt', [pmAddr, '0x0a', 'latest']);
    console.log(`Storage slot 10 (lastAccountedGlobal): ${slot10}`);
    
    const slot11 = await rpcCall('eth_getStorageAt', [pmAddr, '0x0b', 'latest']);
    console.log(`Storage slot 11 (allPremiumsPerSecToStakers): ${slot11}`);
    
    const slot12 = await rpcCall('eth_getStorageAt', [pmAddr, '0x0c', 'latest']);
    console.log(`Storage slot 12 (lastClaimablePremiumsForStakers): ${slot12}`);
    
    const slot13 = await rpcCall('eth_getStorageAt', [pmAddr, '0x0d', 'latest']);
    console.log(`Storage slot 13 (minActiveBalance): ${slot13}`);
    
    // Check if 0x0d has the right value
    if (slot13 && slot13 !== '0x' + '0'.repeat(64)) {
      const minBalFromSlot = BigInt(slot13) / 1000000n;
      console.log(`   minActiveBalance from slot: ${minBalFromSlot.toString()} USDC`);
    }
  } catch (e) {
    console.log('Storage read error:', e.message);
  }

  // Summary
  console.log('\n' + '='.repeat(80));
  console.log('📋 SUMMARY FOR PoC #1');
  console.log('='.repeat(80));
  console.log(`
ProtocolManager address: ${pmAddr}

Global state:
  Total premiums/sec to stakers: ${(allPremiumsPerSec / 1000000n).toString()} USDC/sec
  Claimable premiums total: ${(claimablePremiums / 1000000n).toString()} USDC
  Min active balance: ${(minActiveBalance / 1000000n).toString()} USDC

PoC #1 Trigger Condition: debt > activeBalance
  debt = premiumPerSecond * (block.timestamp - lastAccounted)

IF NO EXISTING PROTOCOL has suitable parameters:
  - Use a mainnet fork to create a test protocol with controlled parameters
  - Set premiumPerSecond high (e.g. 1000 USDC/sec) + activeBalance low (e.g. 100k USDC)
  - After ~500 seconds, debt (500k) > activeBalance (100k)
  - Call protocolUpdate() to trigger _settleProtocolDebt() error
  
This is fully reproducible on a forked mainnet with no real funds needed.
`);
}

main().catch(err => {
  console.error('ERROR:', err.message);
  process.exit(1);
});
