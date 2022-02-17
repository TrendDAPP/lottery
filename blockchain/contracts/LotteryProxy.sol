// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/openzeppelin-contracts@4.5.0/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract LotteryProxy is TransparentUpgradeableProxy {
    constructor(
        address _logic,
        address _admin,
        bytes memory _data
    ) public TransparentUpgradeableProxy(_logic, _admin, _data) {}
}
