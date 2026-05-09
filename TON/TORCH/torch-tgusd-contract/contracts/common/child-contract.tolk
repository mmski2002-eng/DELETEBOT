import "../library/address.tolk";
import "../common/serdes.tolk";
import "../common/types.tolk";

/**
 * @notice Calculates the state initialization and address for a child contract deployed via a base contract.
 * @param deployer The address of the deployer that deploys the child contract.
 * @param contractProof The unique proof used for contract initialization.
 * @param baseCode The base code of the contract.
 * @return (cell, slice) The state initialization cell and the calculated child contract address.
 * @dev 
 * - Used for deploying child contracts like redeemAccount and unstakeAccount. 
 * - It computes the init data using the deployer and contractProof, then combines it with the base code to calculate the contract address. 
 * - The contract will be updated with its actual code and storage after deployment.
 */
@inline
fun getChildContract(deployer: slice, contractProof: ContractProof, baseCode: cell): (cell, slice) {
    // Prepare base contract init
    val baseContractInit: cell = packBaseContractInit(deployer, contractProof);

    // Calculate jetton distributor address
    val stateInit: cell = getStateInit(baseCode, baseContractInit);
    val childContractAddress: slice = getContractAddress(stateInit);

    return (stateInit, childContractAddress);
}