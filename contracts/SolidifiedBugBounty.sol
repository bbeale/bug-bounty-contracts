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

    struct Proposal {
        Severity severity;
        uint256 timestamp;
        bytes32 justification;
        address proponent;
    }

    uint256 constant public automaticApproval = 3 days; 
    uint256 internal projectCount;
    address public dai;
    mapping(address => uint256) public balances;
    mapping(uint256 => bytes32) public projectIdtoHash;
    mapping(uint256 => mapping(uint256 => uint256)) public bugBalances;
    mapping(uint256 => Project) public projects; //Owner => Id => Project
    mapping(uint256 => mapping(uint256 => Bug)) public bugs; //ProjectId => BugId => Bug
    mapping(uint256 => uint256) public bugCount;
    mapping(uint256 => mapping(uint256 => mapping(uint256 => Proposal))) public proposals; //Project Id, Bug Id, Index Proposal
    mapping(uint256 => mapping(uint256 => uint256)) public proposalCount;
    mapping(bytes32 => uint256) public objectBalances; //Non-address balances. For Projects is SHA3(owner, projectID), for Bugs is SHA3(ProjectHash, bugId), for arbitration is SHA3(projectHash, bugHash);

    event ProjectPosted();
    event Deposit();
    event Withdraw();
    event BugAccepted();

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
    
    function pullProject(uint256 projectId) public {
        require(msg.sender == projects[projectId].owner, "Not authorized");
        bytes32 projectHash = projectIdtoHash[projectId];
        sendToAddress(projectHash, msg.sender, objectBalances[projectHash]);
        projects[projectId].status = ProjectStatus.closed;
    }

    function increasePool(uint256 projectId, uint256 _amount) public {
        require(msg.sender == projects[projectId].owner, "Not authorized");
        bytes32 projectHash = projectIdtoHash[projectId];
        sendToObject(msg.sender, projectHash, _amount);
        if(objectBalances[projectIdtoHash[projectId]] >= projects[projectId].rewards[0]){
            projects[projectId].status = ProjectStatus.active;
        }
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
        if(objectBalances[projectIdtoHash[projectId]] < projects[projectId].rewards[0]){
            projects[projectId].status = ProjectStatus.unfunded;
        }
    }

    function acceptBug(uint256 projectId, uint256 bugId) public {
        require(msg.sender == projects[projectId].owner, "Not authorized");
        require(bugs[projectId][bugId].status == BugStatus.pending);
       _acceptBug(projectId, bugId);
    }

    function timeoutAcceptBug(uint256 projectId, uint256 bugId) public {
        require(now.sub(bugs[projectId][bugId].timestamp) >= automaticApproval);
        require(bugs[projectId][bugId].status == BugStatus.pending);
        _acceptBug(projectId, bugId);
    }

    function rejectBug(uint256 projectId, uint256 bugId, bytes32 justification, Severity severity) public {
        require(msg.sender == projects[projectId].owner, "Not authorized");
        bugs[projectId][bugId].status = BugStatus.negotiation;
        proposalCount[projectId][bugId]++;
        proposals[projectId][bugId][proposalCount[projectId][bugId]] = Proposal(severity, now, justification, msg.sender);
    }

    /** 
        TODO The following functions are nasty... a lot of refactor is needed 
    **/

    function acceptProposal(uint256 projectId, uint256 bugId) public {
        address turn = proposalCount[projectId][bugId] % 2 == 0 ? projects[projectId].owner : bugs[projectId][bugId].hunter;
        require(msg.sender == turn || (now.sub(proposals[projectId][bugId][proposalCount[projectId][bugId]].timestamp) > automaticApproval));
        Proposal memory proposal = proposals[projectId][bugId][proposalCount[projectId][bugId]];
        Bug memory bug = bugs[projectId][bugId];
        uint depositDiff = bug.value.div(10).sub(projects[projectId].rewards[uint256(proposal.severity)].div(10));
        bug.value = projects[projectId].rewards[uint256(proposal.severity)];
        bugs[projectId][bugId] = bug;
        _acceptBug(projectId, bugId);
        bytes32 bugHash = keccak256(abi.encodePacked(projectIdtoHash[projectId], bugId));
        sendToAddress(bugHash,bug.hunter, depositDiff);
        __transfer(bugHash, projectIdtoHash[projectId],objectBalances[bugHash]);
    }

    function _acceptBug(uint256 _projectId, uint256 _bugId) internal {
        Bug memory bug = bugs[_projectId][_bugId];
        bug.status = BugStatus.accepted;
        bytes32 bugHash = keccak256(abi.encodePacked(projectIdtoHash[_projectId], _bugId));
        sendToAddress(bugHash,bug.hunter, bug.value.add(bug.value.div(10)));
        bugs[_projectId][_bugId] = bug;
        emit BugAccepted();
    }

    function counterProposal(uint256 projectId, uint256 bugId, bytes32 justification, Severity severity) public {
        address turn = proposalCount[projectId][bugId] % 2 == 0 ? projects[projectId].owner : bugs[projectId][bugId].hunter;
        require(msg.sender == turn);
        proposalCount[projectId][bugId]++;
        proposals[projectId][bugId][proposalCount[projectId][bugId]] = Proposal(severity, now, justification, msg.sender);
    }

    /**
            Arbitration Functions
    **/
    //function sendToArbitration() public {}
    // function commitVote() public {}
    // function revealVote() public {}

    /**
            Administrartive Functions
    **/
    // function upgrade() public {}
    // function changeFee() public {}
    // function flagBugAsRepetivie() public {}


    //getters
    function getProjectDetails(uint256 projectId) external view returns(address owner, bytes32 infoHash, ProjectStatus status, uint256[5] memory rewards, uint256 totalPool) {
        Project memory p = projects[projectId];
        owner = p.owner;
        infoHash = p.infoHash;
        status = p.status;
        rewards = [projects[projectId].rewards[0],projects[projectId].rewards[1],projects[projectId].rewards[2],projects[projectId].rewards[3],projects[projectId].rewards[4]];
        totalPool = objectBalances[projectIdtoHash[projectId]];
    }

    function getBugDetails(uint256 projectId, uint256 bugId) external view returns(address hunter, uint256 timestamp, BugStatus status, uint256 bugValue) {
        Bug memory b = bugs[projectId][bugId];
        hunter = b.hunter;
        timestamp = b.timestamp;
        status = b.status;
        bugValue = b.value;
    }

    function getLatestProposal(uint256 projectId, uint256 bugId) external view returns(address proponent, uint256 timestamp,Severity severity, bytes32 justification) {
        Proposal memory p = proposals[projectId][bugId][proposalCount[projectId][bugId]];
        proponent = p.proponent;
        timestamp = p.timestamp;
        severity = p.severity;
        justification = p.justification;
    }

    //Helper Functions
    function isOrdered(uint256[5] memory _arr) internal pure returns(bool){
        return _arr[0] > _arr[1] && _arr[1] > _arr[2] && _arr[2] > _arr[3] && _arr[3] > _arr[4];
    }
}