"use strict";
const { ethers } = require("ethers");
const provider = new ethers.JsonRpcProvider("https://rpc.api.moonbeam.network");

const FAILED_TX = "0xfd164de94ae08b91e83389dedfc60ba652180dd085fe943847d179925fe6e973";

async function main() {
  const tx = await provider.getTransaction(FAILED_TX);
  const raw = tx.data;

  console.log("Raw calldata length:", raw.length / 2 - 1, "bytes");
  console.log("Selector:", raw.slice(0, 10));
  console.log("");

  // ABI-encoded params: each slot is 32 bytes = 64 hex chars
  // dispatch(address from, address to, uint256 value, bytes data, uint64 gaslimit, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
  // Slot 0: from (address)
  // Slot 1: to (address)
  // Slot 2: value (uint256)
  // Slot 3: data offset (pointer to dynamic bytes)
  // Slot 4: gaslimit (uint64)
  // Slot 5: deadline (uint256)
  // Slot 6: v (uint8)
  // Slot 7: r (bytes32)
  // Slot 8: s (bytes32)

  const slots = [];
  const body = raw.slice(10); // remove selector
  for (let i = 0; i < body.length; i += 64) {
    slots.push(body.slice(i, i + 64));
  }

  const labels = ["from", "to", "value", "bytes_data_offset", "gaslimit", "deadline", "v", "r", "s", "data_length", "data..."];
  slots.forEach((s, i) => {
    const label = labels[i] || "data_" + i;
    let decoded = "";
    if (label === "deadline") {
      const ts = parseInt(s, 16);
      decoded = " => " + ts + " = " + new Date(ts * 1000).toISOString();
    } else if (label === "gaslimit") {
      decoded = " => " + parseInt(s, 16);
    } else if (label === "v") {
      decoded = " => " + parseInt(s, 16);
    } else if (label === "from" || label === "to") {
      decoded = " => 0x" + s.slice(24);
    } else if (label === "data_length") {
      decoded = " => " + parseInt(s, 16) + " bytes";
    }
    console.log("Slot " + i + " [" + label + "]: 0x" + s + decoded);
  });

  // Also decode with ethers to compare
  console.log("\n=== ethers.js decode ===");
  const iface = new ethers.Interface(["function dispatch(address from, address to, uint256 value, bytes data, uint64 gaslimit, uint256 deadline, uint8 v, bytes32 r, bytes32 s)"]);
  const d = iface.decodeFunctionData("dispatch", raw);
  console.log("from:", d.from);
  console.log("to:", d.to);
  console.log("value:", d.value.toString());
  console.log("data:", d.data.slice(0, 18), "...");
  console.log("gaslimit:", d.gaslimit.toString());
  console.log("deadline:", d.deadline.toString(), "=", new Date(Number(d.deadline) * 1000).toISOString());
  console.log("v:", d.v);
  console.log("r:", d.r);
  console.log("s:", d.s);

  // Block timestamp of failed block
  const block = await provider.getBlock(FAILED_TX);
  const blockN = await provider.getBlock(15616976);
  console.log("\nBlock 15616976 timestamp:", blockN.timestamp, "=", new Date(blockN.timestamp * 1000).toISOString());
  console.log("Deadline - block.timestamp:", Number(d.deadline) - blockN.timestamp, "seconds");
  console.log("Deadline expired at block N?", Number(d.deadline) < blockN.timestamp ? "YES (expired)" : "NO (still valid)");
}

main().catch(e => { console.error("FATAL:", e.message); process.exit(1); });
