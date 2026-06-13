POINT 1: “The issue poses no threat to Moonbeam protocol funds, user funds...”

The initial report focused on abuse by relayers, but more on that later. Additional research has revealed a direct financial impact on users:
transaction 0xd5e49fc3e721a70059348b1186f3d7cfa14f52e7ac6af1fefb12eece4e6f862f
Crashed due to future nonce
Nonce rollback confirmed
Replay proven on Chopsticks (AddJoinCode executed)
Any network user could have forced this transaction to execute within an hour. For its owner, however, it may no longer be relevant in <an hour and could result in financial losses due to market changes during that time. Or, due to an error, the owner re-executed the transaction and did not intend to repeat the first one. But any user could force him to do so. Proof of Concept: 1_diode_submitTransaction_replay.js

POINT 2: "Standard relay infrastructure will simulate transactions."
This isn't enough. The vulnerability lies in the CallPermit nonce rollback mechanism, and the team themselves pointed it out to me.
WGLMR = "0xAcc15dC74880C9944775448304B263D191c6077F";
MARKETPLACE = "0x683724817a7d526d6256Aec0D6f8ddF541b924de";
I ran a 50-round experiment on a Moonbeam fork of these contracts, built on Chopsticks, to directly test Moonbeam's stated security measures.
Method: An attacker signs two permits with the same nonce N off-chain (with zero gas cost). Permit A is sent to relayer A, Permit B to relayer B. Relayer A simulates Permit A and sees SUCCESS because nonce N is free during the simulation. Relay B sends Permit B first, consuming nonce N. Relay A sends Permit A and fails with the error "Invalid Permit."
Results over 50 rounds:
- Simulated result: SUCCESS in 50/50 rounds
- Real transaction result: FAILURE in 50/50 rounds
- Cancellation message: "Invalid Permit" (CallPermit's own output)
- Total attack cost: 0 GLMR
Proof of Concept: 2_zero_cost_dos_relayer.js

The simulation cannot protect against this because state changes between the call to eth_call and the inclusion of the block. This is a race condition inherent to blockchains, not a relayer bug. Moonbeam's defenses have been tested and failed 100% of the time.
Based on the actual activity of the Diode Network relayer (balance of 181 GLMR, 459 sends per day), a sustained attack would deplete the relayer's balance in approximately 82 days with zero attack costs. What if we simply multiply this by 1000?

POINT 3: "Standard atomic EVM transaction semantics" do not justify breach of guarantees
The comments in the Moonbeam source code state: "If successful, the EIP712 nonce is incremented to prevent reuse of this permission." (github.com/moonbeam-foundation/moonbeam/blob/master/precompiles/call-permit/CallPermit.sol)
When a subcall is canceled, the nonce value is rolled back, and this guarantee is violated regardless of whether rollback is standard EVM behavior. The metatransaction reference implementation (OpenGSN Forwarder) explicitly separates nonce consumption and subcall success to prevent this particular class of vulnerabilities.
Real-world example with transaction 0xfd164de94ae08b91e83389dedfc60ba652180dd085fe943847d179925fe6e973
Proof of Concept: 3_simulation_insufficiency_proof.js

ITEM 4: "Moonbeam does not manage such relays." Moonbeam publishes the vulnerable template as a recommended practice.
The official Moonbeam guide explicitly lists thirdPartyGasSigner as the recommended pattern for gasless transactions:
docs.moonbeam.network/tutorials/eth-api/call-permit-gasless-txs/
The code in the guide looks like this:
const thirdPartyGasSigner = new ethers.Wallet('INSERT_PRIVATE_KEY', provider);
This is precisely the relay pattern that is vulnerable to zero-cost DoS attacks. I've also included contracts above that use this pattern. Moonbeam cannot simultaneously recommend this pattern to developers and claim that the resulting vulnerability is beyond its capabilities, because "Moonbeam does not use such relays."

Request for review by Immunefi in light of the following circumstances:
1. Direct financial losses to users and infrastructure have been proven to be possible on real MoonBeans contracts. 
2. MoonBeam's security measures have been tested and failed with a 50/50 probability on the MoonBeam fork. The damage is scalable.
3. MoonBeam is publishing information about the vulnerable template as a recommended practice.
4. All QAPs are uploaded to https://gist.github.com/mmski2002-eng/065a4ba2db709c42e878efb34b11d5b9