pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2;

import "./KeysWithPlonkAggVerifier.sol";

// Hardcoded constants to avoid accessing store
contract Verifier is KeysWithPlonkAggVerifier {

    bool constant DUMMY_VERIFIER = false;

    function initialize(bytes calldata) external {
    }

    /// @notice Verifier contract upgrade. Can be external because Proxy contract intercepts illegal calls of this function.
    /// @param upgradeParameters Encoded representation of upgrade parameters
    function upgrade(bytes calldata upgradeParameters) external {}

    function isBlockSizeSupported(uint32 _size) public pure returns (bool) {
        if (DUMMY_VERIFIER) {
            return true;
        } else {
            return isBlockSizeSupportedInternal(_size);
        }
    }

    function verifyMultiblockProof(
        uint256[] calldata _recursiveInput,
        uint256[] calldata _proof,
        uint32[] calldata _block_sizes,
        uint256[] calldata _individual_vks_inputs,
        uint256[] calldata _subproofs_limbs
    ) external view returns (bool) {
        if (DUMMY_VERIFIER) {
            uint oldGasValue = gasleft();
            uint tmp;
            while (gasleft() + 500000 > oldGasValue) {
                tmp += 1;
            }
            return true;
        }
        uint8[] memory vkIndexes = new uint8[](_block_sizes.length);
        for (uint32 i = 0; i < _block_sizes.length; i++) {
            vkIndexes[i] = blockSizeToVkIndex(_block_sizes[i]);
        }
        VerificationKey memory vk = getVkAggregated(uint32(_block_sizes.length));
        return  verify_serialized_proof_with_recursion(_recursiveInput, _proof, VK_TREE_ROOT, VK_MAX_INDEX, vkIndexes, _individual_vks_inputs, _subproofs_limbs, vk);
    }
}
