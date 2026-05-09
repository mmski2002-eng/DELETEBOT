/**
 * Sherlock Protocol Mainnet Query Script
 * 
 * Queries deployed Sherlock contracts on Ethereum mainnet to find:
 * 1. SherlockProtocolManager address
 * 2. Active protocols and their parameters (premium, activeBalance, etc.)
 * 3. Protocols where debt > activeBalance (trigger condition for PoC #1)
 * 
 * Uses public RPC endpoints (no API key required)
 * 
 * Usage: node query_sherlock_onchain.js
 */

const ethers = require('ethers');

// Sherlock v2 Core contract address (from hardhat.config.js)
const SHERLOCK_ADDRESS = '0x0865a889183039689034dA55c1Fd12aF5083eabF';

// Minimal ABI for reading Sherlock storage
const SHERLOCK_ABI = [
  // View functions
  'function yieldStrategy() view returns (address)',
  'function sherlockProtocolManager() view returns (address)',
  'function sherDistributionManager() view returns (address)',
  'function sherlockClaimManager() view returns (address)',
  'function token() view returns (address)',
  'function sher() view returns (address)',
  'function totalTokenBalanceStakers() view returns (uint256)',
  'function totalStakeShares() view returns (uint256)',
  'function nftCounter() view returns (uint256)',
];

// ProtocolManager minimal ABI
const PM_ABI = [
  'function claimablePremiums() view returns (uint256)',
  'function lastClaimablePremiumsForStakers() view returns (uint256)',
  'function minActiveBalance() view returns (uint256)',
  'function allPremiumsPerSecToStakers() view returns (uint256)',
  'function lastAccountedGlobal() view returns (uint256)',
  'function protocolAgent(bytes32) view returns (address)',
  'function premium(bytes32) view returns (uint256)',
  'function activeBalance(bytes32) view returns (uint256)',
  'function secondsOfCoverageLeft(bytes32) view returns (uint256)',
  'function nonStakersClaimable(bytes32) view returns (uint256)',
  'function coverageAmounts(bytes32) view returns (uint256 current, uint256 previous)',
  'function protocolAgent_(bytes32) view returns (address)',
  'function premiums_(bytes32) view returns (uint256)',
  'function activeBalances(bytes32) view returns (uint256)',
  'function lastAccountedEachProtocol(bytes32) view returns (uint256)',
  'function nonStakersPercentage(bytes32) view returns (uint256)',
  'function currentCoverage(bytes32) view returns (uint256)',
  'function previousCoverage(bytes32) view returns (uint256)',
  'function removedProtocolClaimDeadline(bytes32) view returns (uint256)',
];

// Public RPC endpoints (free, no API key needed)
const PUBLIC_RPCS = [
  'https://eth.llamarpc.com',
  'https://rpc.ankr.com/eth',
  'https://eth.drpc.org',
  'https://1rpc.io/eth',
  'https://ethereum.publicnode.com',
];

async function tryConnect() {
  for (const url of PUBLIC_RPCS) {
    try {
      console.log(`⏳ Trying ${url}...`);
      const provider = new ethers.providers.JsonRpcProvider(url, { name: 'mainnet', chainId: 1 });
      const blockNumber = await provider.getBlockNumber();
      console.log(`✅ Connected! Block: ${blockNumber}`);
      return provider;
    } catch (e) {
      console.log(`❌ Failed: ${e.message}`);
    }
  }
  throw new Error('Could not connect to any public RPC');
}

async function main() {
  console.log('='.repeat(80));
  console.log('SHERLOCK PROTOCOL - MAINNET ON-CHAIN QUERY');
  console.log('='.repeat(80));

  const provider = await tryConnect();

  // Step 1: Get Sherlock contract state
  console.log('\n📋 STEP 1: Sherlock Core Contract State');
  console.log('-'.repeat(50));
  const sherlock = new ethers.Contract(SHERLOCK_ADDRESS, SHERLOCK_ABI, provider);

  const sherlockProtocolManager = await sherlock.sherlockProtocolManager();
  const yieldStrategy = await sherlock.yieldStrategy();
  const sherDistributionManager = await sherlock.sherDistributionManager();
  const sherlockClaimManager = await sherlock.sherlockClaimManager();
  const token = await sherlock.token();
  const sher = await sherlock.sher();

  console.log(`Sherlock:              ${SHERLOCK_ADDRESS}`);
  console.log(`ProtocolManager:       ${sherlockProtocolManager}`);
  console.log(`YieldStrategy:         ${yieldStrategy}`);
  console.log(`SherDistributionMgr:   ${sherDistributionManager}`);
  console.log(`ClaimManager:          ${sherlockClaimManager}`);
  console.log(`Token (USDC):          ${token}`);
  console.log(`SHER:                  ${sher}`);

  // Step 2: Get ProtocolManager state
  console.log('\n📋 STEP 2: ProtocolManager Global State');
  console.log('-'.repeat(50));
  const pm = new ethers.Contract(sherlockProtocolManager, PM_ABI, provider);

  const claimablePremiums = await pm.claimablePremiums();
  const minActiveBalance = await pm.minActiveBalance();
  const allPremiumsPerSec = await pm.allPremiumsPerSecToStakers();
  const lastAccountedGlobal = await pm.lastAccountedGlobal();

  console.log(`claimablePremiums:         ${ethers.utils.formatUnits(claimablePremiums, 6)} USDC`);
  console.log(`minActiveBalance:          ${ethers.utils.formatUnits(minActiveBalance, 6)} USDC`);
  console.log(`allPremiumsPerSecToStakers: ${ethers.utils.formatUnits(allPremiumsPerSec, 6)} USDC/sec`);
  console.log(`lastAccountedGlobal:        ${new Date(lastAccountedGlobal.toNumber() * 1000).toISOString()}`);

  // Step 3: Try to find protocols
  // Protocols are identified by bytes32 hash
  // Common Sherlock-covered protocols: known protocol names
  console.log('\n📋 STEP 3: Checking Known Protocols');
  console.log('-'.repeat(50));

  // Known protocols that were covered by Sherlock based on historical data
  const knownProtocolNames = [
    '0x556e697377617000000000000000000000000000000000000000000000000000', // "Uniswap"
    '0x4161766500000000000000000000000000000000000000000000000000000000000000', // "Aave"
    '0x436f6d706f756e640000000000000000000000000000000000000000000000000000', // "Compound"
    '0x4375727665000000000000000000000000000000000000000000000000000000000000', // "Curve"
    '0x42616c616e6365720000000000000000000000000000000000000000000000000000', // "Balancer"
    '0x536e7973000000000000000000000000000000000000000000000000000000000000', // "Snyx/SNX"
    '0x4c696e6b000000000000000000000000000000000000000000000000000000000000', // "Link/Chainlink"
    '0x59656172000000000000000000000000000000000000000000000000000000000000', // "Yearn"
    '0x536f7262000000000000000000000000000000000000000000000000000000000000', // "Sorbet"
    '0x556e69737761705633000000000000000000000000000000000000000000000000', // "UniswapV3"
    '0x4d616b657200000000000000000000000000000000000000000000000000000000', // "Maker"
    '0x4d6f6f6e73686f7400000000000000000000000000000000000000000000000000', // "Moonshot"
    '0x416c67656272610000000000000000000000000000000000000000000000000000', // "Algebra"
    '0x457468657200000000000000000000000000000000000000000000000000000000', // "Ether"
  ];

  // Also try the actual protocol names that Sherlock covered
  const protocolNames = [
    '0x736f72626574746100000000000000000000000000000000000000000000000000', // "sorbetta"
    '0x736869656c64000000000000000000000000000000000000000000000000000000', // "shield"
    '0x616276320000000000000000000000000000000000000000000000000000000000', // "abv2"
    '0x616176653200000000000000000000000000000000000000000000000000000000', // "aave2"
    '0x636f6d706f756e6431000000000000000000000000000000000000000000000000', // "compound1"
  ];

  const allProtocolBytes = [...knownProtocolNames, ...protocolNames];

  let foundAnyProtocol = false;
  for (const protocolBytes of allProtocolBytes) {
    try {
      const agent = await pm.protocolAgent(protocolBytes);
      if (agent !== ethers.constants.AddressZero) {
        foundAnyProtocol = true;
        console.log(`\n🔍 Protocol Found: ${ethers.utils.parseBytes32String(protocolBytes)}`);
        console.log(`   Protocol bytes32: ${protocolBytes}`);
        console.log(`   Agent: ${agent}`);

        const premium = await pm.premium(protocolBytes);
        const activeBal = await pm.activeBalance(protocolBytes);
        const secondsLeft = await pm.secondsOfCoverageLeft(protocolBytes);
        const nonStakersClaim = await pm.nonStakersClaimable(protocolBytes);
        const [currentCov, previousCov] = await pm.coverageAmounts(protocolBytes);

        console.log(`   Premium/sec: ${ethers.utils.formatUnits(premium, 6)} USDC`);
        console.log(`   Active Balance: ${ethers.utils.formatUnits(activeBal, 6)} USDC`);
        console.log(`   Seconds of Coverage Left: ${secondsLeft.toString()}`);
        console.log(`   Current Coverage: ${ethers.utils.formatUnits(currentCov, 6)} USDC`);
        console.log(`   NonStakers Claimable: ${ethers.utils.formatUnits(nonStakersClaim, 6)} USDC`);

        // Check debt condition for PoC #1
        try {
          const lastAccounted = await pm.lastAccountedEachProtocol(protocolBytes);
          const currentBlock = await provider.getBlock('latest');
          const timeDiff = currentBlock.timestamp - lastAccounted.toNumber();
          const debt = premium.mul(timeDiff);

          console.log(`   lastAccounted: ${new Date(lastAccounted.toNumber() * 1000).toISOString()}`);
          console.log(`   Time since last accounting: ${timeDiff} sec`);
          console.log(`   Debt accrued: ${ethers.utils.formatUnits(debt, 6)} USDC`);
          console.log(`   Debt > Active Balance? ${debt.gt(activeBal) ? '⚠️ YES - VULNERABLE!' : '✅ No'}`);
        } catch (e) {
          console.log(`   Could not calculate debt: ${e.message}`);
        }
      }
    } catch (e) {
      // Protocol doesn't exist, skip
    }
  }

  if (!foundAnyProtocol) {
    console.log('\n⚠️ No active protocols found with known names.');
    console.log('Protocols are identified by bytes32 hash - need to find exact protocol names.');
    console.log('\n📋 Alternative approach: Check Sherlock events on Etherscan');
    console.log('ProtocolAdded events would show the protocol bytes32 identifiers.');
    console.log('\nOr use the events from SherlockProtocolManager contract at:');
    console.log(`  ${sherlockProtocolManager}`);
  }

  // Step 4: Summary for PoC #1
  console.log('\n' + '='.repeat(80));
  console.log('📋 SUMMARY FOR PoC #1 (Accounting Error)');
  console.log('='.repeat(80));
  console.log(`
To trigger the accounting error in _settleProtocolDebt(), we need:
  debt = premiumPerSecond * (block.timestamp - lastAccounted) > activeBalance

If no existing protocol has these parameters matching, we would need to:
  A) Wait for a protocol to accumulate enough debt (high premium + long time)
  B) Create a test scenario on a forked mainnet
  
Current global state shows:
  - Total premiums/sec to stakers: ${ethers.utils.formatUnits(allPremiumsPerSec, 6)} USDC/sec
  - Claimable premiums total: ${ethers.utils.formatUnits(claimablePremiums, 6)} USDC
  - Min active balance: ${ethers.utils.formatUnits(minActiveBalance, 6)} USDC
`);

  console.log('\n✅ Query complete!');
}

main().catch(console.error);
