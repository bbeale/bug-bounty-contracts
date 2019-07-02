pragma solidity 0.5.0;
//pragma experimental ABIEncoderV2;

import "./SolidifiedStorage.sol";

contract SolidifiedBugBounty is SolidifiedStorage {

    using SafeMath for uint256;

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
        if(reputation[msg.sender] == 0) reputation[msg.sender] = 50;
        emit Deposit(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) public {
        require(balances[msg.sender] >= _amount, "Not enough funds");
        require(IERC20(dai).transfer(msg.sender,_amount), "External call Falied");
        balances[msg.sender] = balances[msg.sender].sub(_amount);
        emit Withdraw(msg.sender, _amount);
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
        emit ProjectPosted(projectId, projectNumber, msg.sender, ipfsHash, totalPool);
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
        emit PoolIncreased(projectId, msg.sender, objectBalances[projectId]);
    }

    /**
            Bug Functions
    **/
    function postBug(bytes32 bugDescription, bytes32 projectId, Severity severity) public returns(bytes32 bugId) {
        uint256 bugNumber = bugCount[projectId];
        uint256 bugValue = projects[projectId].rewards[uint256(severity)];
        bugId = keccak256(abi.encodePacked(projectId, bugNumber));
        bugs[bugId] = Bug(msg.sender, now, bugValue, BugStatus.pending, severity, projectId);
        sendToObject(msg.sender, bugId, bugValue.div(BUG_STAKE));
        __transfer(projectId, bugId, bugValue);
        bugCount[projectId] = bugCount[projectId].add(1);
        if(objectBalances[projectId] < projects[projectId].rewards[0]){
            projects[projectId].status = ProjectStatus.unfunded;
        }
        emit BugPosted(projectId, bugId, bugNumber,bugDescription, msg.sender, now);
    }

    function acceptBug(bytes32 projectId, bytes32 bugId) public {
        require(msg.sender == projects[projectId].owner, "Not authorized");
        require(bugs[bugId].status == BugStatus.pending, "Bug in the wrong status");
       _acceptBug(bugId);
    }

    function timeoutAcceptBug(bytes32 projectId, bytes32 bugId) public {
        require(now.sub(bugs[bugId].timestamp) >= INTERIM, "No correct time");
        require(bugs[bugId].status == BugStatus.pending, "Bug should be pending");
        _acceptBug(bugId);
    }

    function rejectBug(bytes32 projectId, bytes32 bugId, bytes32 justification, Severity severity) public {
        require(msg.sender == projects[projectId].owner, "Not authorized");
        bugs[bugId].status = BugStatus.negotiation;
        proposalCount[bugId]++;
        proposals[bugId][proposalCount[bugId]] = Proposal(severity, now, justification, msg.sender);
        emit ProposalMade(projectId, bugId, proposalCount[bugId], msg.sender);
    }

    function acceptProposal(bytes32 projectId, bytes32 bugId) public {
        (address turn , ) = inTurn(projectId, bugId);
        require(msg.sender == turn || (now.sub(proposals[bugId][proposalCount[bugId]].timestamp) > INTERIM));
        Proposal memory proposal = proposals[bugId][proposalCount[bugId]];
        Bug memory bug = bugs[bugId];
        uint depositDiff = bug.value.div(BUG_STAKE).sub(projects[projectId].rewards[uint256(proposal.severity)].div(BUG_STAKE));
        bug.value = projects[projectId].rewards[uint256(proposal.severity)];
        bugs[bugId] = bug;
        _acceptBug(bugId);
        sendToAddress(bugId,bug.hunter, depositDiff);
        __transfer(bugId, projectId, objectBalances[bugId]);
    }

    function _acceptBug(bytes32 _bugId) internal {
        Bug memory bug = bugs[_bugId];
        bug.status = BugStatus.accepted;
        sendToAddress(_bugId,bug.hunter, bug.value.add(bug.value.div(BUG_STAKE)));
        bugs[_bugId] = bug;
        emit BugAccepted(bug.projectId, _bugId, bug.hunter, msg.sender);
    }

    function _rejectBug(bytes32 _bugId) internal {
        Bug memory bug = bugs[_bugId];
        bug.status = BugStatus.rejected;
        __transfer(_bugId, bug.projectId, objectBalances[_bugId]);
        bugs[_bugId] = bug;
        emit BugRejected(bug.projectId, _bugId, bug.hunter, msg.sender);
    }

    function counterProposal(bytes32 projectId, bytes32 bugId, bytes32 justification, Severity severity) public {
       (address proposer,) = inTurn(projectId, bugId);
        require(msg.sender == proposer, "Not current proposer");
        proposalCount[bugId]++;
        proposals[bugId][proposalCount[bugId]] = Proposal(severity, now, justification, msg.sender);
        emit ProposalMade(projectId, bugId, proposalCount[bugId], msg.sender);
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
        arbitrations[arbitrationId] = Arbitration(msg.sender,defendant,now,0, bugId);
        emit ArbitrationRequested(projectId, bugId, arbitrationId, plaintiff, defendant, now);
    }

    function acceptArbitration(bytes32 arbitrationId) public {
        require(msg.sender == arbitrations[arbitrationId].defendant);
        sendToObject(msg.sender, arbitrationId, ARBITRATION_FEE);
        arbitrations[arbitrationId].commitPeriod = now;
        Arbitration memory arb = arbitrations[arbitrationId];
        emit ArbitrationAccepted(bugs[arb.bugId].projectId, arb.bugId, arbitrationId, arb.plaintiff, arb.defendant, now);
    }

    function rejectArbitration(bytes32 arbitrationId) public {
        Arbitration memory arb = arbitrations[arbitrationId];
        require(msg.sender == arb.defendant || (now.sub(arb.timestamp) > INTERIM), "Invalid msg.sender or time");
        sendToAddress(arbitrationId, arb.plaintiff, ARBITRATION_FEE);
        __transfer(arbitrationId, arb.bugId, objectBalances[arbitrationId]);
        arb.plaintiff == bugs[arb.bugId].hunter ? _acceptBug(arb.bugId) : _rejectBug(arb.bugId);
        emit ArbitrationRejected(bugs[arb.bugId].projectId, arb.bugId, arbitrationId, arb.plaintiff, arb.defendant, now);
    }

    function commitVote(bytes32 arbitrationId, bytes32 commit) public {
        Arbitration memory arbitration = arbitrations[arbitrationId];
        require(msg.sender != arbitration.plaintiff && msg.sender != arbitration.defendant, "Invalid voter");
        //require that the voter has any reputation
        require(arbitration.commitPeriod <= now && now <= arbitration.commitPeriod.add(INTERIM), "Invalid voting period");
        sendToObject(msg.sender, arbitrationId, VOTING_FEE);
        commits[arbitrationId][msg.sender] = commit;
    }

    function revealCommit(bytes32 arbitrationId, uint256 vote, bytes32 salt) public {
        require(vote  == 1 || vote == 2); //Make this an ENUM
        Arbitration memory arb = arbitrations[arbitrationId];
        require(now >= arb.commitPeriod.add(INTERIM));
        bool validVote = keccak256(abi.encodePacked(vote, salt)) == commits[arbitrationId][msg.sender];
        if(validVote) votes[arbitrationId][msg.sender] = vote;
        if(validVote && canVote(msg.sender, arbitrationId) && voters[arbitrationId][4] != address(0)){
            //Refund voting stake of last voters
            sendToAddress(arbitrationId, voters[arbitrationId][4], VOTING_FEE);
        }
        address[5] memory vot = insertVoteM(msg.sender, voters[arbitrationId]);
        voters[arbitrationId] = vot;
    }

    function slashCommit(bytes32 arbitrationId, uint256 vote, bytes32 salt, address voter) public {
        require(now.sub(arbitrations[arbitrationId].commitPeriod) < INTERIM, "too late to slash");
        bool validVote = keccak256(abi.encodePacked(vote, salt)) == commits[arbitrationId][voter];
        if(validVote) {
            //How to deal with double voting?
            commits[arbitrationId][voter] = bytes32(0);
            sendToAddress(arbitrationId, msg.sender, VOTING_FEE);
        }
    }
    /**
            Administrartive Functions
    **/
    // function upgrade() public {}
    // function changeFee() public {}
    // function flagBugAsRepetivie() public {}


    function insertVote(address voter, address[5] storage votersArray) internal {
       for(uint i = 4; i > 0; i--){
           if(reputation[votersArray[i - 1]] >= reputation[voter]) {
            votersArray[i] = voter;
            break;
           }
           votersArray[i] = votersArray[i - 1];
           votersArray[i - 1] = voter;
       }
    }

    function insertVoteM(address voter, address[5] memory votersArray) internal view returns(address[5] memory){
       for(uint i = 4; i > 0; i--){
           if(reputation[votersArray[i - 1]] >= reputation[voter]) {
            votersArray[i] = voter;
            break;
           }
           votersArray[i] = votersArray[i - 1];
           votersArray[i - 1] = voter;
       }
    }

    function canVote(address voter, bytes32 arbitrationId) public view returns(bool){
        if(reputation[voters[arbitrationId][4]] < reputation[voter]) return false;
        bool voted;
        for(uint256 i = 0; i < 5; i++) {
            if(voters[arbitrationId][i] == voter) voted = true;
        }
        return !voted;
    }

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