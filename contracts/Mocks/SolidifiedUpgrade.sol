pragma solidity 0.5.0;
//pragma experimental ABIEncoderV2;

import ".././SolidifiedStorage.sol";

contract SolidifiedUpgrade is SolidifiedStorage {

    using SafeMath for uint256;
    using SafeMath for uint32;


    function initialize(address _dai) public {
        require(!initialized);
        dai = _dai;
        projectCount =  100;
        initialized = true;
    }
}