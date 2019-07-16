pragma solidity 0.5.0;

import "./SolidifiedStorage.sol";
import "../node_modules/openzeppelin-solidity/contracts/ownership/Ownable.sol";
/**
 * @title Proxy
 * @dev Gives the possibility to delegate any call to a foreign implementation.
 */
contract SolidifiedProxy is SolidifiedStorage, Ownable {

   address public implementation;
   address public newImpl;
   uint256 public upgradeTime;
   bytes initData;

   event UpgradeStarted(address currentImplementation, address proposedImplementation, address starter, uint256 upgradeTime);
   event UpgradeFinalized(address newImplementation, address sender, uint256 upgradeTime);

  constructor(address _impl, bytes memory _initData) public {
    implementation = _impl;
    //implementation.delegatecall(initData);
    (bool suc, ) = implementation.delegatecall(_initData);
    if(!suc) revert();
  }

  function startUpgrade(address _newImpl, bytes memory _initData) public onlyOwner {
      require(_newImpl != address(0));
      newImpl = _newImpl;
      upgradeTime = now + 3 days;
      initData = _initData;
      emit UpgradeStarted(implementation, newImpl, msg.sender, upgradeTime);
  }

  function finalizeUpgrade() public {
      require(now >= upgradeTime);
      require(newImpl != address(0));
      initialized = false;
      implementation = newImpl;
      (bool suc, ) = implementation.delegatecall(initData);
      if(!suc) revert();
      newImpl = address(0);
      upgradeTime = 0;
      delete initData;
      emit UpgradeFinalized(implementation, msg.sender, now);
  }

  /**
  * @dev Fallback function allowing to perform a delegatecall to the given implementation.
  * This function will return whatever the implementation call returns
  */
  function() payable external {
    address _impl = implementation;
    assembly {
      let ptr := mload(0x40)
      calldatacopy(ptr, 0, calldatasize)
      let result := delegatecall(gas, _impl, ptr, calldatasize, 0, 0)
      let size := returndatasize
      returndatacopy(ptr, 0, size)

      switch result
      case 0 { revert(ptr, size) }
      default { return(ptr, size) }
    }
  }
}
