pragma solidity 0.5.0;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";
import "../node_modules/openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

contract SolidifiedBugBounty {

    using SafeMath for uint256;

    enum Severity { Critical, Major, Medium, Minor, Note}
    enum BugStatus { pending, accepted, rejected, negotiation, arbitration}
    enum ProjectStatus {active, unfunded, closed}

    struct Project {
        address owner;
        bytes32 infoHash;
        ProjectStatus status;
        mapping(uint256 => uint256) rewards; // Severity to reqerd value
    }

    struct Bug {
        address hunter;
        uint256 timestamp;
        uint256 value;
        BugStatus status;
        Severity severity;
    }

    // struct Rewards {
    //     uint256 Critical;
    //     uint256 Major;
    //     uint256 Medium;
    //     uint256 Minor;
    //     uint256 Suggestion;
    // }

    uint256 internal projectCount;
    address public dai;
    mapping(address => uint256) public balances;
    mapping(uint256 => bytes32) public projectIdtoHash;
    mapping(uint256 => mapping(uint256 => uint256)) public bugBalances;
    mapping(uint256 => Project) public projects; //Owner => Id => Project
    mapping(uint256 => mapping(uint256 => Bug)) public bugs; //ProjectId => BugId => Bug
    mapping(uint256 => uint256) public bugCount;

    mapping(bytes32 => uint256) public objectBalances; //Non-address balances. For Projects is SHA3(owner, projectID), for Bugs is SHA3(ProjectHash, bugId), for arbitration is SHA3(projectHash, bugHash);

    event ProjectPosted();
    event Deposit();
    event Withdraw();

    constructor(address _dai) public {
        dai = _dai; 
        projectCount++;
    }

    /**
            Balance Functions
    **/
    function deposit(uint256 _amount) public {
        require(IERC20(dai).transferFrom(msg.sender, address(this),_amount), "transferFrom Dai failed");
        balances[msg.sender] = balances[msg.sender].add(_amount);
        emit Deposit();
    }

    function withdraw(uint256 _amount) public {
        require(balances[msg.sender] >= _amount);
        require(IERC20(dai).transfer(msg.sender,_amount));
        balances[msg.sender] = balances[msg.sender].sub(_amount);
        emit Withdraw();
    }

    function __transfer(address _from, address _to, uint256 _amount) internal {
        balances[_from] = balances[_from].sub(_amount);
        balances[_to] = balances[_to].add(_amount);
    }

    function __transfer(bytes32 _from, bytes32 _to, uint256 _amount) internal {
        objectBalances[_from] = objectBalances[_from].sub(_amount);
        objectBalances[_to] = objectBalances[_to].add(_amount);
    }

    // //Move funds between users and objetcs(Pool, Bug, Arbitration, etc)
    function sendToObject(address origin, bytes32 object, uint256 _amount) internal {
        balances[origin] = balances[origin].sub(_amount);
        objectBalances[object] = objectBalances[object].add(_amount);
    }

    function sendToAddress(bytes32 origin, address dest, uint256 _amount) internal {
        objectBalances[origin] = objectBalances[origin].sub(_amount);
        balances[dest] = balances[dest].add(_amount);
        
    }
    /**
            Contract Posting Functions
    **/
    function postProject(bytes32 ipfsHash, uint256 totalPool, uint256[5] memory _rewardsValue) public returns(uint256 projectId){
        require(isOrdered(_rewardsValue), "Rewards must be ordered");
        require(totalPool >= _rewardsValue[0], "totalPool should be greater than critical reward");
        projectId = projectCount;
        projects[projectId] = Project(msg.sender, ipfsHash, ProjectStatus.active);
        for(uint i = 0; i < _rewardsValue.length; i++){
            projects[projectId].rewards[i] = _rewardsValue[i];
        }
        bytes32 projectHash = keccak256(abi.encodePacked(msg.sender, projectId));
        projectIdtoHash[projectId] = projectHash;
        sendToObject(msg.sender, projectHash, totalPool);
        emit ProjectPosted();
        projectCount++;
    }
    
    // function updateProject() public {}
    // function increasePool() public {}
    function pullProject(uint256 projectId) public {
        require(msg.sender == projects[projectId].owner, "Not authorized");
        bytes32 projectHash = projectIdtoHash[projectId];
        sendToAddress(projectHash, msg.sender, objectBalances[projectHash]);
        projects[projectId].status = ProjectStatus.closed;
    }
    
    /**
            Bug Functions
    **/
    function postBug(bytes32 bugDescription, uint256 projectId, Severity severity) public {
        uint256 bugId = bugCount[projectId];
        uint256 bugValue = projects[projectId].rewards[uint256(severity)];
        bugs[projectId][bugId] = Bug(msg.sender, now, bugValue, BugStatus.pending, severity);
        bytes32 bugHash = keccak256(abi.encodePacked(projectIdtoHash[projectId], bugId));
        sendToObject(msg.sender, bugHash, bugValue.div(10));
        __transfer(projectIdtoHash[projectId], bugHash, bugValue);
        bugCount[projectId] = bugCount[projectId].add(1);
    }
    // function acceptBug() public {}
    // function rejectBug() public{}
    // function timeoutAccept() public {}

    /**
            Arbitration Functions
    **/
    // function sendToArbitration() public {}
    // function commitVote() public {}
    // function revealVote() public {}

    /**
            Administrartive Functions
    **/
    // function upgrade() public {}
    // function changeFee() public {}
    // function flagBugAsRepetivie() public {}


    //getters
    function getProjectDetails(uint256 projectId) public view returns(address owner, bytes32 infoHash, ProjectStatus status, uint256[5] memory rewards, uint256 totalPool) {
        Project memory p = projects[projectId];
        owner = p.owner;
        infoHash = p.infoHash;
        status = p.status;
        rewards = [projects[projectId].rewards[0],projects[projectId].rewards[1],projects[projectId].rewards[2],projects[projectId].rewards[3],projects[projectId].rewards[4]];
        totalPool = objectBalances[projectIdtoHash[projectId]];
    }

    //Helper Functions
    function isOrdered(uint256[5] memory _arr) internal pure returns(bool){
        return _arr[0] > _arr[1] && _arr[1] > _arr[2] && _arr[2] > _arr[3] && _arr[3] > _arr[4];
    }
    
}