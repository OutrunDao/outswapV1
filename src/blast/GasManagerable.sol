//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {IBlast} from "./IBlast.sol";

abstract contract GasManagerable {
    IBlast public constant BLAST = IBlast(0x4300000000000000000000000000000000000002); // TODO update when mainnet

    address public gasManager;

    error GasZeroAddress();

    error UnauthorizedAccount(address account);

    event ClaimMaxGas(address indexed recipient, uint256 gasAmount);

    event GasManagerTransferred(address indexed previousGasManager, address indexed newGasManager);

    constructor(address initialGasManager) {
        require(initialGasManager != address(0), GasZeroAddress());

        _transferGasManager(initialGasManager);

        BLAST.configureClaimableGas();
    }

    modifier onlyGasManager() {
        address msgSender = msg.sender;
        require(gasManager == msgSender, UnauthorizedAccount(msgSender));
        
        _;
    }

    /**
     * @dev Read all gas remaining balance 
     */
    function readGasBalance() external view onlyGasManager returns (uint256) {
        (, uint256 gasBanlance, , ) = BLAST.readGasParams(address(this));
        return gasBanlance;
    }

    /**
     * @dev Claim max gas of this contract
     * @param recipient - Address of receive gas
     */
    function claimMaxGas(address recipient) external onlyGasManager returns (uint256 gasAmount) {
        require(recipient != address(0), GasZeroAddress());

        gasAmount = BLAST.claimMaxGas(address(this), recipient);

        emit ClaimMaxGas(recipient, gasAmount);
    }

    function transferGasManager(address newGasManager) public onlyGasManager {
        require(newGasManager != address(0), GasZeroAddress());

        _transferGasManager(newGasManager);
    }

    function _transferGasManager(address newGasManager) internal {
        address oldGasManager = gasManager;
        gasManager = newGasManager;

        emit GasManagerTransferred(oldGasManager, newGasManager);
    }
}