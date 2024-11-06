//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {GasManagerable} from "../blast/GasManagerable.sol";
import {Initializable} from "../libraries/Initializable.sol";
import {TransferHelper} from "../libraries/TransferHelper.sol";
import {IOutrunAMMPair} from "./interfaces/IOutrunAMMPair.sol";
import {IOutrunAMMFactory} from "./interfaces/IOutrunAMMFactory.sol";
import {IOutrunAMMYieldVault} from "./interfaces/IOutrunAMMYieldVault.sol";

contract OutrunAMMYieldVault is IOutrunAMMYieldVault, Initializable, GasManagerable {
    address public immutable SY_BETH;
    address public immutable SY_USDB;

    address public facotry;

    constructor(
        address _SY_BETH, 
        address _SY_USDB,  
        address _gasManager
    ) GasManagerable(_gasManager) {
        SY_BETH = _SY_BETH;
        SY_USDB = _SY_USDB;
    }

    function isValidPair(address pair) public view override returns (bool) {
        (address token0, address token1) = IOutrunAMMPair(pair).getPairTokens();
        (address tokenA, address tokenB) = token0 < token1 ? (token0, token1) : (token1, token0);
        return IOutrunAMMFactory(facotry).getPair(tokenA, tokenB) == pair;
    }

    function initialize(address _facotry) external override initializer {
        facotry = _facotry;
    }

    function claimBETHNativeYield(address pair, address maker) external override {
        require(isValidPair(pair), InValidPair());
        require(maker != address(0) || pair != address(0), ZeroInput());
        
        IOutrunAMMPair(pair).updateAndDistributeYields(maker);
        (, uint128 accruedYield) = IOutrunAMMPair(pair).makerBETHNativeYields(maker);
        TransferHelper.safeTransfer(SY_BETH, maker, accruedYield);
        IOutrunAMMPair(pair).clearBETHNativeYield(maker);

        emit ClaimBETHNativeYield(pair, maker, accruedYield);
    }

    function claimUSDBNativeYield(address pair, address maker) external override {
        require(isValidPair(pair), InValidPair());
        require(maker != address(0) || pair != address(0), ZeroInput());

        IOutrunAMMPair(pair).updateAndDistributeYields(maker);
        (, uint128 accruedYield) = IOutrunAMMPair(pair).makerUSDBNativeYields(maker);
        TransferHelper.safeTransfer(SY_USDB, maker, accruedYield);
        IOutrunAMMPair(pair).clearUSDBNativeYield(maker);

        emit ClaimUSDBNativeYield(pair, maker, accruedYield);
    }
}
