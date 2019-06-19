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

    struct Arbitration {
        address plaintiff;
        address defendant;
        uint256 timestamp;
        uint256 commitPeriod;
    }

    uint256 constant public INTERIM = 3 days;
    uint256 constant public ARBITRATION_FEE = 10 ether;
    uint256 constant public VOTING_FEE = 10 ether;
    uint256 constant public BUG_STAKE = 10;

    address public dai;

    mapping(address => uint256) public balances;
    mapping(bytes32 => uint256) public objectBalances;

    mapping(uint256 => bytes32) public projectNumberToId;
    mapping(uint256 => mapping(uint256 => bytes32)) public bugNumberToId;
    mapping(uint256 => mapping(uint256 => bytes32)) public arbitrationNumberToId;

    mapping(bytes32 => Project) public projects;
    mapping(bytes32 => Bug) public bugs;
    mapping(bytes32 => Arbitration) public arbitrations;
    mapping(bytes32 => mapping(uint256 => Proposal)) public proposals;

    mapping(bytes32 => uint256) public bugCount;
    mapping(bytes32 => uint256) public proposalCount;
    uint256 internal projectCount;

    mapping(bytes32 => mapping(address => bytes32)) public commits;
    mapping(bytes32 => mapping(address => uint)) public votes;

    event ProjectPosted(bytes32 Id, address Owner);
    event ProjectPulled(bytes32 Id, address Owner, uint256 time);
    event BugPosted(bytes32 projectId, bytes32 bugId, address hunter);
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
        require(balances[msg.sender] >= _amount, "Not enough funds");
        require(IERC20(dai).transfer(msg.sender,_amount), "External call Falied");
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
    function postProject(bytes32 ipfsHash, uint256 totalPool, uint256[5] memory _rewardsValue) public returns(bytes32 projectId){
        require(isOrdered(_rewardsValue), "Rewards must be ordered");
        require(totalPool >= _rewardsValue[0], "totalPool should be greater than critical reward");
        uint256 projectNumber = projectCount;
        projectCount++;
        projectId = keccak256(abi.encodePacked(msg.sender, projectNumber));
        projects[projectId] = Project(msg.sender, ipfsHash, ProjectStatus.active);
        for(uint i = 0; i < _rewardsValue.length; i++){
            projects[projectId].rewards[i] = _rewardsValue[i];
        }
        projectNumberToId[projectNumber] = projectId;
        sendToObject(msg.sender, projectId, totalPool);
        emit ProjectPosted(projectId, msg.sender);
    }

    function pullProject(bytes32 projectId) public {
        require(msg.sender == projects[projectId].owner, "Not authorized");
        sendToAddress(projectId, msg.sender, objectBalances[projectId]);
        projects[projectId].status = ProjectStatus.closed;
        emit ProjectPulled(projectId, msg.sender, now);
    }


    function increasePool(bytes32 projectId, uint256 _amount) public {
        require(msg.sender == projects[projectId].owner, "Not authorized");
        sendToObject(msg.sender, projectId, _amount);
        if (objectBalances[projectId] >= projects[projectId].rewards[0])
            projects[projectId].status = ProjectStatus.active;
    }

    /**
            Bug Functions
    **/
    function postBug(bytes32 bugDescription, bytes32 projectId, Severity severity) public returns(bytes32 bugId) {
        uint256 bugNumber = bugCount[projectId];
        uint256 bugValue = projects[projectId].rewards[uint256(severity)];
        bugId = keccak256(abi.encodePacked(projects[projectId], bugNumber));
        bugs[bugId] = Bug(msg.sender, now, bugValue, BugStatus.pending, severity);
        sendToObject(msg.sender, bugId, bugValue.div(BUG_STAKE));
        __transfer(projectId, bugId, bugValue);
        bugNumber[projectId] = bugNumber[projectId].add(1);
        if(objectBalances[projectId] < projects[projectId].rewards[0]){
            projects[projectId].status = ProjectStatus.unfunded;
        }
        emit BugPosted(projectId, bugId, msg.sender);
    }

    function acceptBug(bytes32 projectId, bytes32 bugId) public {
        require(msg.sender == projects[projectId].owner, "Not authorized");
        require(bugs[bugId].status == BugStatus.pending, "Bug in the wrong status");
       _acceptBug(projectId, bugId);
    }

    function timeoutAcceptBug(bytes32 projectId, bytes32 bugId) public {
        require(now.sub(bugs[bugId].timestamp) >= INTERIM, "No correct time");
        require(bugs[bugId].status == BugStatus.pending, "Bug should be pending" );
        _acceptBug(projectId, bugId);
    }

    function rejectBug(bytes32 projectId, bytes32 bugId, bytes32 justification, Severity severity) public {
        require(msg.sender == projects[projectId].owner, "Not authorized");
        bugs[bugId].status = BugStatus.negotiation;
        proposalCount[bugId]++;
        proposals[bugId][proposalCount[bugId]] = Proposal(severity, now, justification, msg.sender);
    }

    /**
        TODO The following functions are nasty... a lot of refactor is needed
    **/

    function acceptProposal(bytes32 projectId, bytes32 bugId) public {
        (address turn , ) = inTurn(projectId, bugId);
        require(msg.sender == turn || (now.sub(proposals[bugId][proposalCount[bugId]].timestamp) > INTERIM));
        Proposal memory proposal = proposals[bugId][proposalCount[bugId]];
        Bug memory bug = bugs[bugId];
        uint depositDiff = bug.value.div(BUG_STAKE).sub(projects[projectId].rewards[uint256(proposal.severity)].div(BUG_STAKE));
        bug.value = projects[projectId].rewards[uint256(proposal.severity)];
        bugs[bugId] = bug;
        _acceptBug(projectId, bugId);
        sendToAddress(bugId,bug.hunter, depositDiff);
        __transfer(bugId, projectId, objectBalances[bugId]);
    }

    function _acceptBug(bytes32 _projectId, bytes32 _bugId) internal {
        Bug memory bug = bugs[_bugId];
        bug.status = BugStatus.accepted;
        sendToAddress(_bugId,bug.hunter, bug.value.add(bug.value.div(BUG_STAKE)));
        bugs[_bugId] = bug;
        emit BugAccepted();
    }

    function counterProposal(bytes32 projectId, bytes32 bugId, bytes32 justification, Severity severity) public {
       (address proposer,) = inTurn(projectId, bugId);
        require(msg.sender == proposer, "Not current proposer");
        proposalCount[bugId]++;
        proposals[bugId][proposalCount[bugId]] = Proposal(severity, now, justification, msg.sender);
    }

    /**
            Arbitration Functions
    **/
    function sendToArbitration(bytes32 projectId, bytes32 bugId) public returns(bytes32 arbitrationId){
        require(proposalCount[bugId] > 1, "Not enough proposals");
        (address plaintiff, address defendant) = inTurn(projectId, bugId);
        require(msg.sender == plaintiff, "Invalid Sender");
        arbitrationId = keccak256(abi.encodePacked(projectId, bugId));
        sendToObject(msg.sender, arbitrationId, ARBITRATION_FEE);
        arbitrations[arbitrationId] = Arbitration(msg.sender,defendant,now,0);
    }

    function acceptArbitration(bytes32 arbitrationId) public {
        require(msg.sender == arbitrations[arbitrationId].defendant);
        sendToObject(msg.sender, arbitrationId, ARBITRATION_FEE);
        arbitrations[arbitrationId].commitPeriod = now;
    }

    function commitVote(bytes32 arbitrationId, bytes32 commit) public {
        Arbitration memory arbitration = arbitrations[arbitrationId];
        require(msg.sender != arbitration.plaintiff && msg.sender != arbitration.defendant, "Invalid voter");
        //require that the voter has any reputation
        require(arbitration.commitPeriod <= now && now <= arbitration.commitPeriod.add(INTERIM), "Invalid voting period");
        sendToObject(msg.sender, arbitrationId, VOTING_FEE);
        commits[arbitrationId][msg.sender] = commit;
    }

    /**
            Administrartive Functions
    **/
    // function upgrade() public {}
    // function changeFee() public {}
    // function flagBugAsRepetivie() public {}


    //getters
    function getProjectDetails(bytes32 projectId)
        external
        view
        returns(address owner, bytes32 infoHash, ProjectStatus status, uint256[5] memory rewards, uint256 totalPool) {
        Project memory p = projects[projectId];
        owner = p.owner;
        infoHash = p.infoHash;
        status = p.status;
        rewards = [
            projects[projectId].rewards[0],
            projects[projectId].rewards[1],
            projects[projectId].rewards[2],
            projects[projectId].rewards[3],
            projects[projectId].rewards[4] ];
        totalPool = objectBalances[projectId];
    }

    function getBugDetails(bytes32 bugId)
        external
        view
        returns(address hunter, uint256 timestamp, BugStatus status, uint256 bugValue) {
        Bug memory b = bugs[bugId];
        hunter = b.hunter;
        timestamp = b.timestamp;
        status = b.status;
        bugValue = b.value;
    }

    function getLatestProposal(bytes32 bugId)
        external
        view
        returns(address proponent, uint256 timestamp,Severity severity, bytes32 justification) {
        Proposal memory p = proposals[bugId][proposalCount[bugId]];
        proponent = p.proponent;
        timestamp = p.timestamp;
        severity = p.severity;
        justification = p.justification;
    }

    function getArbitrationDetails(bytes32 arbitrationId)
        external
        view
        returns(address plaintiff , address defendant, uint256 timestamp, uint256 commitPeriod) {
        Arbitration memory a = arbitrations[arbitrationId];
        plaintiff = a.plaintiff;
        defendant = a.defendant;
        timestamp = a.timestamp;
        commitPeriod = a.commitPeriod;
    }

    //Helper Functions
    function isOrdered(uint256[5] memory _arr) internal pure returns(bool){
        return _arr[0] > _arr[1] && _arr[1] > _arr[2] && _arr[2] > _arr[3] && _arr[3] > _arr[4];
    }

    function inTurn(bytes32 _projectId, bytes32 _bugId) internal view returns(address first, address second) {
        first = proposalCount[_bugId] % 2 == 0 ? projects[_projectId].owner : bugs[_bugId].hunter;
        second = proposalCount[_bugId] % 2 == 1 ? projects[_projectId].owner : bugs[_bugId].hunter;
    }
}