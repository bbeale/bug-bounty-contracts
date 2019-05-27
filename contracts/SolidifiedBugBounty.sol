pragma solidity 0.5.8;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";
import "../node_modules/openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

contract SolidifiedBugBounty {

    using SafeMath for uint256;

    enum Severity { Critical, Major, Medium, Minor, Note}
    enum BugStatus { pending, accepted, rejected, negotiation, arbitration}
    enum ProjectStatus {draft, active, unfunded, closed}

    struct Project {
        uint256 id;
        address owner;
        bytes32 infoHash;
        uint256 Pool;
        mapping(bool => Rewards) rewards;
        mapping(uint256 => Bug) bugs;
    }

    struct Bug {
        address hunter;
        Severity severity;
    }

    struct Rewards {
        uint256 Critical;
        uint256 Major;
        uint256 Medium;
        uint256 Minor;
        uint256 Suggestion;
    }

    uint256 internal projectCount;
    address public dai;
    mapping(address => uint256) public balances;
    mapping(uint256 => Project) public projects; //Owner => Id => Project
    mapping(uint => mapping(uint256 => Bug)) public bugs; //ProjectId => BugId => Bug

    event ProjectPosted();
    event Deposit();

    constructor(address _dai) public {
        dai = _dai; 
        projectCount++;
    }

    /**
            Balance Functions
    **/
    function deposit(uint256 _amount) public {
        require(IERC20(dai).transferFrom(msg.sender, address(this),_amount));
        balances[msg.sender] = balances[msg.sender].add(_amount);
        emit Deposit();
    }

    function withdraw(uint256 _amount) public {
        require(balances[msg.sender] >= _amount);
        require(IERC20(dai).transfer(msg.sender,_amount));
        balances[msg.sender] = balances[msg.sender].sub(_amount);
        emit Deposit();
    }

    // function sendTip() public {}

    // //Move funds between users and objetcs(Pool, Bug, Arbitration, etc)
    // function sendToPool(address origin, uint256 poolId, uint256 amount) public {}
    // function sendToBug() public {}

    /**
            Contract Posting Functions
    **/
    function postProject(bytes32 ipfsHash, uint256 totalPool, uint256[5] memory _rewardsValue) public {
        require(isOrdered(_rewardsValue));
        require(totalPool >= _rewardsValue[0]);
        //Add hash to projects mapping
        projects[projectCount] = Project(projectCount, msg.sender, ipfsHash, totalPool);
        projects[projectCount].rewards[true] = Rewards(_rewardsValue[0],_rewardsValue[1],_rewardsValue[2],_rewardsValue[3],_rewardsValue[4]);
        //sendToPool(msg.sender, projectCount, totalPool);
        emit ProjectPosted();
        projectCount++;
    }
    
    function updateProject() public {}
    function increasePool() public {}
    function pullProject() public {}
    
    /**
            Bug Functions
    **/
    function postBug() public {}
    function acceptBug() public {}
    function rejectBug() public{}
    function timeoutAccept() public {}

    /**
            Arbitration Functions
    **/
    function sendToArbitration() public {}
    function commitVote() public {}
    function revealVote() public {}

    /**
            Administrartive Functions
    **/
    function upgrade() public {}
    function changeFee() public {}
    function flagBugAsRepetivie() public {}

    //Helper Functions
    function isOrdered(uint256[5] memory _arr) internal pure returns(bool){
        return _arr[0] > _arr[1] && _arr[1] > _arr[2] && _arr[2] > _arr[3] && _arr[3] > _arr[4];
    }
}


