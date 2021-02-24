pragma solidity ^0.5.0;

import "./ReentrancyGuard.sol";
import "./SafeMath.sol";
import "./SafeMathUInt128.sol";
import "./SafeCast.sol";
import "./Utils.sol";

import "./Storage.sol";
import "./Config.sol";
import "./Events.sol";
import "./PairTokenManager.sol";

import "./uniswap/interfaces/IUniswapV2Pair.sol";

contract ZkSyncExit is PairTokenManager, Storage, Config, Events, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeMathUInt128 for uint128;

    /// @notice Withdraws token from Franklin to root chain in case of exodus mode. User must provide proof that he owns funds
    /// @param _accountId Id of the account in the tree
    /// @param _proof Proof
    /// @param _tokenId Verified token id
    /// @param _amount Amount for owner (must be total amount, not part of it)
    function exit(uint32 _accountId, uint16 _tokenId, uint128 _amount, uint256[] calldata _proof) external nonReentrant {
        bytes22 packedBalanceKey = packAddressAndTokenId(msg.sender, _tokenId);
        require(exodusMode, "fet11"); // must be in exodus mode
        require(!exited[_accountId][_tokenId], "fet12"); // already exited
        require(verifierExit.verifyExitProof(blocks[totalBlocksVerified].stateRoot, _accountId, msg.sender, _tokenId, _amount, _proof), "fet13"); // verification failed

        uint128 balance = balancesToWithdraw[packedBalanceKey].balanceToWithdraw;
        balancesToWithdraw[packedBalanceKey].balanceToWithdraw = balance.add(_amount);
        exited[_accountId][_tokenId] = true;
    }

    function updateBalance(uint16 _tokenId, uint128 _out) internal {
        bytes22 packedBalanceKey0 = packAddressAndTokenId(msg.sender, _tokenId);
        uint128 balance0 = balancesToWithdraw[packedBalanceKey0].balanceToWithdraw;
        balancesToWithdraw[packedBalanceKey0].balanceToWithdraw = balance0.add(_out);
    }

    function checkLpL1Balance(address pair, uint128 _lpL1Amount) internal {
        //Check lp_L1_amount
        uint128 balance0 = uint128(IUniswapV2Pair(pair).balanceOf(msg.sender));
        require(_lpL1Amount == balance0, "le6");

        //burn lp token
        if (balance0 > 0) {
            pairmanager.burn(address(pair), msg.sender, SafeCast.toUint128(_lpL1Amount)); //
        }
    }

    function checkPairAccount(address _pairAccount, uint16[] memory _tokenIds) view internal {
        // check the pair account is correct with token id
        uint16 token = validatePairTokenAddress(_pairAccount);
        require(token == _tokenIds[0], "le4");

        // make sure token0/token1 is pair account
        address _token0 = governance.getTokenAddress(_tokenIds[1]);
        if (_tokenIds[1] != 0) {
            require(_token0 != address(0), "le8");
        } else {
            _token0 = address(0);
        }
        address _token1 = governance.getTokenAddress(_tokenIds[2]);
        if (_tokenIds[2] != 0) {
            require(_token1 != address(0), "le7");
        } else {
            _token1 = address(0);
        }
        address pair = pairmanager.getPair(_token0, _token1);
        require(pair == _pairAccount, "le5");
    }

    function lpExit(bytes32 _rootHash, uint32[] calldata _accountIds, address[] calldata _addresses, uint16[] calldata _tokenIds, uint128[] calldata _amounts, uint256[] calldata _proof) external nonReentrant {
        /* data format:
           bytes32 _rootHash
            _owner_id = _accountIds[0]
            _pair_acc_id = _accountIds[1]
            _owner_addr = _addresses[0]
            _pair_acc_addr = _addresses[1]
            _lp_token_id = _tokenIds[0]
            _token0_id = _tokenIds[1]
            _token1_id = _tokenIds[2]
            _lp_L2_amount = _amounts[0]
            _lp_L1_amount = _amounts[1]
            _balance0 = _amounts[2]
            _balance1 = _amounts[3]
            _out0 = _amounts[4]
            _out1 = _amounts[5]
        */
        //check root hash
        require(exodusMode, "le0"); // must be in exodus mode
        require(_rootHash == blocks[totalBlocksVerified].stateRoot, "le1");
        //check owner _account
        require(msg.sender == _addresses[0], "le2");
        uint32 _accountId = _accountIds[0];
        uint32 _pairAccountId = _accountIds[1];
        checkPairAccount(_addresses[1], _tokenIds);
        checkLpL1Balance(_addresses[1], _amounts[1]);
        // check (token0, out0)
        updateBalance(_tokenIds[1], _amounts[4]);
        // check (token1, out1)
        updateBalance(_tokenIds[2], _amounts[5]);
        require(!swap_exited[_accountId][_pairAccountId], "le3"); // already exited
        bytes memory _account_data = abi.encodePacked(_rootHash, _accountId, _addresses[0], _amounts[0], _amounts[1]);
        bytes memory _pair_data0 = abi.encodePacked(_pairAccountId, _addresses[1], _tokenIds[0], _tokenIds[1], _tokenIds[2]);
        bytes memory _pair_data1 = abi.encodePacked(_amounts[2], _amounts[3], _amounts[4], _amounts[5]);
        require(verifierExit.verifyLpExitProof(_account_data, _pair_data0, _pair_data1, _proof), "levf"); // verification failed
        swap_exited[_accountId][_pairAccountId] = true;
    }
}
