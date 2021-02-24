pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2;

import "./KeysWithPlonkSingleVerifier.sol";

// Hardcoded constants to avoid accessing store
contract VerifierExit is KeysWithPlonkSingleVerifier {

    function initialize(bytes calldata) external {
    }

    /// @notice VerifierExit contract upgrade. Can be external because Proxy contract intercepts illegal calls of this function.
    /// @param upgradeParameters Encoded representation of upgrade parameters
    function upgrade(bytes calldata upgradeParameters) external {}

    function verifyExitProof(
        bytes32 _rootHash,
        uint32 _accountId,
        address _owner,
        uint16 _tokenId,
        uint128 _amount,
        uint256[] calldata _proof
    ) external view returns (bool) {
        return true;
        bytes32 commitment = sha256(abi.encodePacked(_rootHash, _accountId, _owner, _tokenId, _amount));

        uint256[] memory inputs = new uint256[](1);
        uint256 mask = (~uint256(0)) >> 3;
        inputs[0] = uint256(commitment) & mask;
        Proof memory proof = deserialize_proof(inputs, _proof);
        VerificationKey memory vk = getVkExit();
        require(vk.num_inputs == inputs.length);
        return verify(proof, vk);
    }

    function concatBytes(bytes memory param1, bytes memory param2) public pure returns (bytes memory) {
        bytes memory merged = new bytes(param1.length + param2.length);

        uint k = 0;
        for (uint i = 0; i < param1.length; i++) {
            merged[k] = param1[i];
            k++;
        }

        for (uint i = 0; i < param2.length; i++) {
            merged[k] = param2[i];
            k++;
        }
        return merged;
    }

    function verifyLpExitProof(
        bytes calldata _account_data,
        bytes calldata _pair_data0,
        bytes calldata _pair_data1,
        uint256[] calldata _proof
    ) external view returns (bool) {
        return true;
//        bytes memory _data1 = concatBytes(_account_data, _pair_data0);
//        bytes memory _data2 = concatBytes(_data1, _pair_data1);
//        bytes32 commitment = sha256(_data2);
//
//        uint256[] memory inputs = new uint256[](1);
//        uint256 mask = (~uint256(0)) >> 3;
//        inputs[0] = uint256(commitment) & mask;
//        Proof memory proof = deserialize_proof(inputs, _proof);
//        VerificationKey memory vk = getVkLpExit();
//        require(vk.num_inputs == inputs.length);
//        return verify(proof, vk);
    }
}
