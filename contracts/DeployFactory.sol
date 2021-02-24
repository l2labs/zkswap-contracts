pragma solidity >=0.5.0 <0.7.0;

import "./Governance.sol";
import "./uniswap/UniswapV2Factory.sol";
import "./Proxy.sol";
import "./UpgradeGatekeeper.sol";
import "./ZkSync.sol";
import "./Verifier.sol";
import "./VerifierExit.sol";
import "./TokenInit.sol";

contract DeployFactory is TokenDeployInit {

    // Why do we deploy contracts in the constructor?
    //
    // If we want to deploy Proxy and UpgradeGatekeeper (using new) we have to deploy their contract code with this contract
    // in total deployment of this contract would cost us around 2.5kk of gas and calling final transaction
    // deployProxyContracts would cost around 3.5kk of gas(which is equivalent but slightly cheaper then doing deploy old way by sending
    // transactions one by one) but doing this in one method gives us simplicity and atomicity of our deployment.
    //
    // If we use selfdesctruction in the constructor then it removes overhead of deploying Proxy and UpgradeGatekeeper
    // with DeployFactory and in total this constructor would cost us around 3.5kk, so we got simplicity and atomicity of
    // deploy without overhead.
    //
    // `_feeAccountAddress` argument is not used by the constructor itself, but it's important to have this
    // information as a part of a transaction, since this transaction can be used for restoring the tree
    // state. By including this address to the list of arguments, we're making ourselves able to restore
    // genesis state, as the very first account in tree is a fee account, and we need its address before
    // we're able to start recovering the data from the Ethereum blockchain.
    constructor(
        Governance _govTarget, UniswapV2Factory _pairTarget, address _blockCommit, address _exit, Verifier _verifierTarget, VerifierExit _verifierExitTarget, ZkSync _zkSyncTarget,
        bytes32 _genesisRoot, address _firstValidator, address _governor,
        address _feeAccountAddress
    ) public {
        require(_firstValidator != address(0));
        require(_governor != address(0));
        require(_feeAccountAddress != address(0));

        deployProxyContracts(_govTarget, _pairTarget, _blockCommit, _exit, _verifierTarget, _verifierExitTarget, _zkSyncTarget, _genesisRoot, _firstValidator, _governor);

        selfdestruct(msg.sender);
    }

    event Addresses(address governance, address zksync, address verifier, address pair, address gatekeeper);
    event AddressesOther(address commitblock, address exit, address verifierexit);

    function deployProxyContracts(
        Governance _governanceTarget, UniswapV2Factory _pairTarget, address _blockCommit, address _exit, Verifier _verifierTarget, VerifierExit _verifierExitTarget, ZkSync _zksyncTarget,
        bytes32 _genesisRoot, address _validator, address _governor
    ) internal {

        Proxy governance = new Proxy(address(_governanceTarget), abi.encode(this));
        Proxy pair = new Proxy(address(_pairTarget), abi.encode());
        // set this contract as governor
        Proxy verifier = new Proxy(address(_verifierTarget), abi.encode());
        Proxy verifierExit = new Proxy(address(_verifierExitTarget), abi.encode());
        Proxy zkSync = new Proxy(address(_zksyncTarget), abi.encode(address(governance), address(verifier), address(verifierExit), address(pair)));
        ZkSync(address(zkSync)).setGenesisRootAndAddresses(_genesisRoot, _blockCommit, _exit);

        /* set zksync address */
        UniswapV2Factory(address(pair)).setZkSyncAddress(address(zkSync));

	UpgradeGatekeeper upgradeGatekeeper = new UpgradeGatekeeper(zkSync);

        governance.transferMastership(address(upgradeGatekeeper));
        upgradeGatekeeper.addUpgradeable(address(governance));

        pair.transferMastership(address(upgradeGatekeeper));
        upgradeGatekeeper.addUpgradeable(address(pair));

        verifier.transferMastership(address(upgradeGatekeeper));
        upgradeGatekeeper.addUpgradeable(address(verifier));

        verifierExit.transferMastership(address(upgradeGatekeeper));
        upgradeGatekeeper.addUpgradeable(address(verifierExit));

        zkSync.transferMastership(address(upgradeGatekeeper));
        upgradeGatekeeper.addUpgradeable(address(zkSync));

        upgradeGatekeeper.transferMastership(_governor);

        emit Addresses(address(governance), address(zkSync), address(verifier), address(pair), address(upgradeGatekeeper));
        emit AddressesOther(_blockCommit, _exit, address(verifierExit));

        finalizeGovernance(Governance(address(governance)), _validator, _governor);
    }

    function finalizeGovernance(Governance _governance, address _validator, address _finalGovernor) internal {
        address[] memory tokens = getTokens();
        for (uint i = 0; i < tokens.length; ++i) {
            _governance.addToken(tokens[i]);
        }
        _governance.setValidator(_validator, true);
        _governance.changeGovernor(_finalGovernor);
    }
}
