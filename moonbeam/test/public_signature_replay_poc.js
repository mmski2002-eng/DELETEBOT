const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const solc = require("solc");
const { ethers } = require("ethers");
const ganache = require("ganache");

async function waitReceipt(provider, hash) {
  for (let i = 0; i < 50; i++) {
    const receipt = await provider.send("eth_getTransactionReceipt", [hash]);
    if (receipt) return receipt;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error(`Timed out waiting for ${hash}`);
}

function compile() {
  const sources = {
    "MockCallPermit.sol": {
      content: fs.readFileSync(path.join(__dirname, "..", "contracts", "MockCallPermit.sol"), "utf8"),
    },
    "TransientTarget.sol": {
      content: fs.readFileSync(path.join(__dirname, "..", "contracts", "TransientTarget.sol"), "utf8"),
    },
  };

  const input = {
    language: "Solidity",
    sources,
    settings: {
      optimizer: { enabled: true, runs: 200 },
      viaIR: true,
      evmVersion: "paris",
      outputSelection: {
        "*": {
          "*": ["abi", "evm.bytecode.object"],
        },
      },
    },
  };

  const output = JSON.parse(solc.compile(JSON.stringify(input)));
  const errors = (output.errors || []).filter((item) => item.severity === "error");
  assert.equal(errors.length, 0, JSON.stringify(errors, null, 2));
  return output.contracts;
}

async function main() {
  const contracts = compile();
  const mnemonic = "test test test test test test test test test test test junk";
  const provider = new ethers.BrowserProvider(
    ganache.provider({
      logging: { quiet: true },
      wallet: { mnemonic, totalAccounts: 4, defaultBalance: 100 },
      chain: { chainId: 31337, hardfork: "shanghai" },
    })
  );

  const user = ethers.HDNodeWallet.fromPhrase(mnemonic, undefined, "m/44'/60'/0'/0/0").connect(provider);
  const relayerA = await provider.getSigner(1);
  const relayerB = await provider.getSigner(2);

  const MockCallPermit = new ethers.ContractFactory(
    contracts["MockCallPermit.sol"].MockCallPermit.abi,
    contracts["MockCallPermit.sol"].MockCallPermit.evm.bytecode.object,
    relayerA
  );
  const TransientTarget = new ethers.ContractFactory(
    contracts["TransientTarget.sol"].TransientTarget.abi,
    contracts["TransientTarget.sol"].TransientTarget.evm.bytecode.object,
    relayerA
  );

  const callPermit = await MockCallPermit.deploy();
  await callPermit.waitForDeployment();
  const target = await TransientTarget.deploy();
  await target.waitForDeployment();

  const from = await user.getAddress();
  const to = await target.getAddress();
  const value = 0n;
  const gaslimit = 1000000n;
  const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);
  const amount = 7n;

  await (await target.mintCredits(from, amount)).wait();

  const data = target.interface.encodeFunctionData("spendCredits", [from, amount]);
  const nonce = await callPermit.nonces(from);

  const domain = {
    name: "Call Permit Precompile",
    version: "1",
    chainId: 31337,
    verifyingContract: await callPermit.getAddress(),
  };
  assert.equal(await callPermit.DOMAIN_SEPARATOR(), ethers.TypedDataEncoder.hashDomain(domain));
  const types = {
    CallPermit: [
      { name: "from", type: "address" },
      { name: "to", type: "address" },
      { name: "value", type: "uint256" },
      { name: "data", type: "bytes" },
      { name: "gaslimit", type: "uint64" },
      { name: "nonce", type: "uint256" },
      { name: "deadline", type: "uint256" },
    ],
  };
  const message = { from, to, value, data, gaslimit, nonce, deadline };
  const signature = ethers.Signature.from(await user.signTypedData(domain, types, message));
  assert.equal(ethers.verifyTypedData(domain, types, message, signature.serialized), from);

  const dispatchArgs = [
    from,
    to,
    value,
    data,
    gaslimit,
    deadline,
    signature.v,
    signature.r,
    signature.s,
  ];
  const publicCalldata = callPermit.interface.encodeFunctionData("dispatch", dispatchArgs);
  assert.ok(publicCalldata.startsWith("0xb5ea0966"), "encoded calldata must be dispatch(...)");

  await assert.rejects(
    callPermit.connect(relayerA).dispatch(...dispatchArgs),
    /TransientTarget: disabled|missing revert data|execution reverted/
  );
  assert.equal((await callPermit.nonces(from)).toString(), "0", "nonce must remain unconsumed after revert");
  assert.equal((await target.spent(from)).toString(), "0", "failed dispatch must not execute action");

  await (await target.setEnabled(true)).wait();
  assert.equal(await target.enabled(), true, "target must be enabled before replay");
  assert.equal((await target.credits(from)).toString(), amount.toString(), "credits must exist before replay");
  await provider.call({
    from: await relayerB.getAddress(),
    to,
    data,
    gasLimit: 1000000,
  });
  await provider.call({
    from: await relayerB.getAddress(),
    to: await callPermit.getAddress(),
    data: publicCalldata,
    gasLimit: 3000000,
  });

  const replayHash = await provider.send("eth_sendTransaction", [{
    from: await relayerB.getAddress(),
    to: await callPermit.getAddress(),
    data: publicCalldata,
    gas: "0x2dc6c0",
  }]);
  const replayReceipt = await waitReceipt(provider, replayHash);
  assert.equal(replayReceipt.status, "0x1", "replay transaction must succeed");

  assert.equal((await callPermit.nonces(from)).toString(), "1", "nonce should increase only after success");
  assert.equal((await target.spent(from)).toString(), amount.toString(), "same signature executed later");

  console.log(JSON.stringify({
    user: from,
    firstDispatcher: await relayerA.getAddress(),
    replayDispatcher: await relayerB.getAddress(),
    replayTx: replayHash,
    samePublicCalldata: publicCalldata,
    nonceAfterFailedDispatch: "0",
    nonceAfterReplaySuccess: "1",
    spentAfterReplay: amount.toString(),
  }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
