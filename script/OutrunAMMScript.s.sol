// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "./BaseScript.s.sol";
import {IOutrunDeployer} from "./IOutrunDeployer.sol";
import {OutrunAMMPair} from "../src/core/OutrunAMMPair.sol";
import {OutrunAMMERC20} from "../src/core/OutrunAMMERC20.sol";
import {OutrunAMMRouter} from "../src/router/OutrunAMMRouter.sol";
import {OutrunAMMYieldVault} from "../src/core/OutrunAMMYieldVault.sol";
import {OutrunAMMFactory, IOutrunAMMFactory} from "../src/core/OutrunAMMFactory.sol";

contract OutrunAMMScript is BaseScript {
    address internal WETH;
    address internal USDB;
    address internal SY_BETH;
    address internal SY_USDB;
    address internal OUTRUN_DEPLOYER;

    address internal owner;
    address internal blastGovernor;
    address internal pointsOperator;
    address internal feeTo;

    function run() public broadcaster {
        owner = vm.envAddress("OWNER");
        feeTo = vm.envAddress("FEE_TO");
        SY_BETH = vm.envAddress("SY_BETH");
        SY_USDB = vm.envAddress("SY_USDB");
        OUTRUN_DEPLOYER = vm.envAddress("OUTRUN_DEPLOYER");
        
        blastGovernor = vm.envAddress("BLAST_GOVERNOR");
        pointsOperator = vm.envAddress("POINTS_OPERATOR");
        WETH = vm.envAddress("BLAST_SEPOLIA_WETH");
        USDB = vm.envAddress("BLAST_SEPOLIA_USDB");
        
        console.log("Pair initcode:");
        console.logBytes32(keccak256(abi.encodePacked(type(OutrunAMMPair).creationCode, abi.encode(blastGovernor))));

        // 0.3% fee
        (, address factory0) = _deployVaultAndFactory(30, 2);

        // 1% fee
        (, address factory1) = _deployVaultAndFactory(100, 2);

        // OutrunAMMRouter
        _deployOutrunAMMRouter(factory0, factory1, 2);

        _getDeployedFactory(30, 2);
        _getDeployedFactory(100, 2);
    }

    function _getDeployedFactory(uint256 swapFeeRate, uint256 nonce) internal view returns (address deployed) {
        bytes32 salt = keccak256(abi.encodePacked("MemeverseLauncher", swapFeeRate, nonce));
        deployed = IOutrunDeployer(OUTRUN_DEPLOYER).getDeployed(owner, salt);

        console.log("%d fee OutrunAMMFactory deployed on %s", swapFeeRate, deployed);
    }

    function _deployVaultAndFactory(uint256 swapFeeRate, uint256 nonce) internal returns (address yieldVaultAddr, address factoryAddr) {
        address factory = swapFeeRate == 30 ? vm.envAddress("30_OUTRUN_AMM_FACTORY") 
            : swapFeeRate == 100 ? vm.envAddress("100_OUTRUN_AMM_FACTORY") : address(0);
        OutrunAMMYieldVault yieldVault = new OutrunAMMYieldVault(SY_BETH, SY_USDB, factory, blastGovernor);
        yieldVaultAddr = address(yieldVault);

        // Deploy OutrunAMMFactory By OutrunDeployer
        bytes32 salt = keccak256(abi.encodePacked("OutrunAMMFactory", swapFeeRate, nonce));
        bytes memory creationCode = abi.encodePacked(
            type(OutrunAMMFactory).creationCode,
            abi.encode(owner, blastGovernor, WETH, USDB, yieldVaultAddr, pointsOperator, swapFeeRate)
        );
        factoryAddr = IOutrunDeployer(OUTRUN_DEPLOYER).deploy(salt, creationCode);
        IOutrunAMMFactory(factoryAddr).setFeeTo(feeTo);

        console.log("%d fee OutrunAMMYieldVault deployed on %s", swapFeeRate, yieldVaultAddr);
        console.log("%d fee OutrunAMMFactory deployed on %s", swapFeeRate, factoryAddr);
    }

    function _deployOutrunAMMRouter(address factory0, address factory1, uint256 nonce) internal {
        // Deploy OutrunAMMFactory By OutrunDeployer
        bytes32 salt = keccak256(abi.encodePacked("OutrunAMMRouter", nonce));
        bytes memory creationCode = abi.encodePacked(
            type(OutrunAMMRouter).creationCode,
            abi.encode(factory0, factory1, WETH, blastGovernor)
        );
        address routerAddr = IOutrunDeployer(OUTRUN_DEPLOYER).deploy(salt, creationCode);

        console.log("OutrunAMMRouter deployed on %s", routerAddr);
    }
}
