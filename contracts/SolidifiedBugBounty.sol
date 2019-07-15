pragma solidity 0.5.0;
//pragma experimental ABIEncoderV2;

import "./SolidifiedStorage.sol";

contract SolidifiedBugBounty is SolidifiedStorage {

    using SafeMath for uint256;
    using SafeMath for uint32;


    uint256 constant public INTERIM = 3 days;
    uint256 constant public ARBITRATION_FEE = 10 ether;
    uint256 constant public VOTING_FEE = 10 ether;
    uint256 constant public BUG_STAKE = 10;
    uint256 constant public MINIMUN_QUORUM = 5;

    constructor(address _dai) public {
        dai = _dai;
        projectCount++;
    }

    function giveReputationTEST(address[] memory add, uint256[] memory amounts) public {
        for(uint i = 0; i < add.length; i++){
            reputation[add[i]] = amounts[i];
        }
    }

    /**
            Balance Functions
    **/
    function deposit(uint256 _amount) public {
        require(IERC20(dai).transferFrom(msg.sender, address(this),_amount));
        balances[msg.sender] = balances[msg.sender].add(_amount);
        if(reputation[msg.sender] == 0) reputation[msg.sender] = 50;
        emit Deposit(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) public {
        require(balances[msg.sender] >= _amount);
        require(IERC20(dai).transfer(msg.sender,_amount));
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
            Project Posting Functions
    **/
    function postProject(bytes32 ipfsHash, uint256 totalPool, uint256[5] memory _rewardsValue) public returns(bytes32 projectId){
        require(isOrdered(_rewardsValue));
        require(totalPool >= _rewardsValue[0]);
        uint256 projectNumber = projectCount;
        projectCount++;
        projectId = keccak256(abi.encodePacked(msg.sender, projectNumber));
        projects[projectId] = Project(msg.sender, ProjectStatus.active);
        for(uint i = 0; i < _rewardsValue.length; i++){
            projects[projectId].rewards[i] = _rewardsValue[i];
        }
        sendToObject(msg.sender, projectId, totalPool);
        emit ProjectPosted(projectId, projectNumber, msg.sender, ipfsHash, totalPool);
    }

    function pullProject(bytes32 projectId) public {
        require(msg.sender == projects[projectId].owner);
        sendToAddress(projectId, msg.sender, objectBalances[projectId]);
        projects[projectId].status = ProjectStatus.closed;
        emit ProjectPulled(projectId, msg.sender, now);
    }


    function increasePool(bytes32 projectId, uint256 _amount) public {
        require(msg.sender == projects[projectId].owner);
        sendToObject(msg.sender, projectId, _amount);
        if (objectBalances[projectId] >= projects[projectId].rewards[0])
            projects[projectId].status = ProjectStatus.active;
        emit PoolIncreased(projectId, msg.sender, objectBalances[projectId]);
    }

    /**
            Bug Functions
    **/
    function postBug(bytes32 bugDescription, bytes32 projectId, Severity severity) public returns(bytes32 bugId) {
        require(projects[projectId].status == ProjectStatus.active);
        uint256 bugNumber = bugCount[projectId];
        uint256 bugValue = projects[projectId].rewards[uint256(severity)];
        bugId = keccak256(abi.encodePacked(projectId, bugNumber));
        bugs[bugId] = Bug(msg.sender, BugStatus.pending, severity, uint32(now), projectId);
        sendToObject(msg.sender, bugId, bugValue.div(BUG_STAKE));
        __transfer(projectId, bugId, bugValue);
        bugCount[projectId] = bugCount[projectId].add(1);
        if(objectBalances[projectId] < projects[projectId].rewards[0]){
            projects[projectId].status = ProjectStatus.unfunded;
        }
        emit BugPosted(projectId, bugId, bugNumber,bugDescription, msg.sender, now);
    }

    function acceptBug(bytes32 projectId, bytes32 bugId) public {
        require(msg.sender == projects[projectId].owner || now.sub(bugs[bugId].timestamp) >= INTERIM);
        require(bugs[bugId].status == BugStatus.pending);
       _resolveBug(bugId);
    }

    function rejectBug(bytes32 projectId, bytes32 bugId, bytes32 justification, Severity severity) public {
        require(msg.sender == projects[projectId].owner);
        require(uint256(bugs[bugId].severity) <= uint256(severity));
        bugs[bugId].status = BugStatus.negotiation;
        proposalCount[bugId]++;
        proposals[bugId][proposalCount[bugId]] = Proposal(severity, uint32(now));
        emit ProposalMade(projectId, bugId, justification, proposalCount[bugId], msg.sender);
    }

    function _resolveBug(bytes32 _bugId) internal {
       Bug memory bug = bugs[_bugId];
       uint256 bugValue = projects[bug.projectId].rewards[uint256(bug.severity)];
       if(bugValue > 0){
           //acept Bug
           bug.status = BugStatus.accepted;
           sendToAddress(_bugId,bug.hunter, bugValue.add(bugValue.div(BUG_STAKE)));
           emit BugAccepted(bug.projectId, _bugId, bug.hunter, msg.sender);
       } else {
           //reject Bug
           bug.status = BugStatus.rejected;
           __transfer(_bugId, bug.projectId, objectBalances[_bugId]);
           emit BugRejected(bug.projectId, _bugId, bug.hunter, msg.sender);
       }
       bugs[_bugId] = bug;
    }

    function acceptProposal(bytes32 projectId, bytes32 bugId) public {
        (address turn , ) = inTurn(projectId, bugId);
        require(msg.sender == turn || (now.sub(proposals[bugId][proposalCount[bugId]].timestamp) > INTERIM));
        Proposal memory proposal = proposals[bugId][proposalCount[bugId]];
        Bug memory bug = bugs[bugId];
        uint256 bugValue = projects[projectId].rewards[uint256(bug.severity)];
        uint depositDiff = bugValue.div(BUG_STAKE).sub(projects[projectId].rewards[uint256(proposal.severity)].div(BUG_STAKE));
        bug.severity = proposal.severity;
        bugs[bugId] = bug;
        _resolveBug(bugId);
        sendToAddress(bugId,bug.hunter, depositDiff);
        __transfer(bugId, projectId, objectBalances[bugId]);
    }

    function counterProposal(bytes32 projectId, bytes32 bugId, bytes32 justification, Severity severity) public {
       (address proposer,) = inTurn(projectId, bugId);
        require(msg.sender == proposer);
        require(uint256(bugs[bugId].severity) <= uint256(severity));
        proposalCount[bugId]++;
        proposals[bugId][proposalCount[bugId]] = Proposal(severity, uint32(now));
        emit ProposalMade(projectId, bugId, justification, proposalCount[bugId], msg.sender);
    }

    /**
            Arbitration Functions
    **/
    function sendToArbitration(bytes32 projectId, bytes32 bugId) public returns(bytes32 arbitrationId){
        uint256 proposalNumber = proposalCount[bugId];
        require(proposalNumber > 1);
        (address plaintiff, address defendant) = inTurn(projectId, bugId);
        require(msg.sender == plaintiff);
        arbitrationId = keccak256(abi.encodePacked(projectId, bugId));
        sendToObject(msg.sender, arbitrationId, ARBITRATION_FEE);
        __transfer(bugId, arbitrationId, objectBalances[bugId]);
        arbitrations[arbitrationId] = Arbitration(msg.sender,defendant,0,uint32(0),uint32(now),bugId);
        emit ArbitrationRequested(projectId, bugId, arbitrationId, plaintiff, defendant, now);
    }

    function acceptArbitration(bytes32 arbitrationId) public {
        Arbitration memory arb = arbitrations[arbitrationId];
        require(msg.sender == arb.defendant);
        sendToObject(msg.sender, arbitrationId, ARBITRATION_FEE);
        arbitrations[arbitrationId].commitPeriod = uint32(now.add(INTERIM));
        emit ArbitrationAccepted(bugs[arb.bugId].projectId, arb.bugId, arbitrationId, arb.plaintiff, arb.defendant, now);
    }

    function rejectArbitration(bytes32 arbitrationId) public {
        Arbitration memory arb = arbitrations[arbitrationId];
       require(msg.sender == arb.defendant || arb.requestTime.add(INTERIM) < now);
        sendToAddress(arbitrationId, arb.plaintiff, ARBITRATION_FEE);
        __transfer(arbitrationId, arb.bugId, objectBalances[arbitrationId]);
        //get last proposal and update bug
        bugs[arb.bugId].severity = proposals[arb.bugId][proposalCount[arb.bugId]].severity;
        _resolveBug(arb.bugId);
        emit ArbitrationRejected(bugs[arb.bugId].projectId, arb.bugId, arbitrationId, arb.plaintiff, arb.defendant, now);
    }

    function commitVote(bytes32 arbitrationId, bytes32 commit) public {
        Arbitration memory arbitration = arbitrations[arbitrationId];
        require(msg.sender != arbitration.plaintiff && msg.sender != arbitration.defendant);
        require(reputation[msg.sender] > 0);
        require(arbitration.commitPeriod > 0 && now <= arbitration.commitPeriod);
        require(commits[arbitrationId][msg.sender] == bytes32(0));

        arbitrations[arbitrationId].votersCount = uint32(arbitrations[arbitrationId].votersCount.add(1));
        sendToObject(msg.sender, arbitrationId, VOTING_FEE);
        commits[arbitrationId][msg.sender] = commit;
    }

    function revealCommit(bytes32 arbitrationId, Ruling vote, bytes32 salt) public {
        Arbitration memory arb = arbitrations[arbitrationId];
        require(arb.votersCount >= MINIMUN_QUORUM);
        bool validVote = keccak256(abi.encodePacked(uint256(vote), salt)) == commits[arbitrationId][msg.sender];
        if(validVote){
           votes[arbitrationId][msg.sender] = vote;
           commits[arbitrationId][msg.sender] = bytes32(0);
           if(reputation[voters[arbitrationId][4]] < reputation[msg.sender]) {
               if(voters[arbitrationId][4] != address(0)){
                   sendToAddress(arbitrationId, voters[arbitrationId][4], VOTING_FEE);
               }
               address[5] memory vot = insertVote(msg.sender, voters[arbitrationId]);
               voters[arbitrationId] = vot;
           } else {
               sendToAddress(arbitrationId, msg.sender, VOTING_FEE);
           }
        }
    }

    function slashCommit(bytes32 arbitrationId, uint256 vote, bytes32 salt, address voter) public {
        require(now < arbitrations[arbitrationId].commitPeriod);
        bool validVote = keccak256(abi.encodePacked(vote, salt)) == commits[arbitrationId][voter];
        if(validVote) {
            commits[arbitrationId][voter] = bytes32(0);
            sendToAddress(arbitrationId, msg.sender, VOTING_FEE);
        }
    }

    function insertVote(address voter, address[5] memory votersArray) internal returns(address[5] memory){
        if(reputation[voter] <= reputation[votersArray[4]]) return votersArray;
        for(uint i = 4; i > 0; i--){

           if(reputation[votersArray[i - 1]] >= reputation[voter]) {
            votersArray[i] = voter;
            break;
           }
           votersArray[i] = votersArray[i - 1];
           votersArray[i - 1] = voter;
       }
       return votersArray;
    }


    function tallyVotes(bytes32 arbitrationId) public view returns(uint256 plaintiffVotes, uint256 defendantVotes, Ruling winner){
        address[5] memory voters = voters[arbitrationId];
        for(uint i = 0; i < voters.length; i++){
            if(votes[arbitrationId][voters[i]] == Ruling.plaintiff) plaintiffVotes++;
            if(votes[arbitrationId][voters[i]] == Ruling.defendant) defendantVotes++;
        }
        winner = plaintiffVotes > defendantVotes ? Ruling.plaintiff : Ruling.defendant;
    }

    function updateVotersStakes(bytes32 arbitrationId) internal returns(address[] memory) {
        address[5] memory allVoters = voters[arbitrationId];
        uint256 totalPool = VOTING_FEE.mul(5).add(ARBITRATION_FEE);
        (uint256 plaintiffVotes, uint256 defendantVotes, Ruling ruling) = tallyVotes(arbitrationId);
        uint256 winnigVotes = ruling == Ruling.plaintiff ? plaintiffVotes : defendantVotes;
        for(uint i = 0; i < allVoters.length; i++){
            if(votes[arbitrationId][allVoters[i]] == ruling) {
                //Voter voted according to the jury
               sendToAddress(arbitrationId, allVoters[i], totalPool.div(winnigVotes).sub(1)); //Possible to have rounding errors
               reputation[msg.sender] = reputation[msg.sender].add(200);
            } else {
                reputation[msg.sender] = reputation[msg.sender] > 200 ? reputation[msg.sender] - 200 : 0;
            }
        }
    }

    function resolveArbitration(bytes32 arbitrationId) public {
        require(now > arbitrations[arbitrationId].commitPeriod.add(INTERIM.mul(2)));
        Arbitration memory arb = arbitrations[arbitrationId];
        (, , Ruling winner) = tallyVotes(arbitrationId);
        uint256 lastProposal = proposalCount[arb.bugId];
        uint proposalNumber = winner == Ruling.plaintiff ? lastProposal : lastProposal - 1;
        Proposal memory prop = proposals[arb.bugId][proposalNumber];
        bugs[arb.bugId].severity =  prop.severity;
        updateVotersStakes(arbitrationId);
        address winnerAddress = winner == Ruling.plaintiff ? arb.plaintiff : arb.defendant;
        sendToAddress(arbitrationId, winnerAddress, ARBITRATION_FEE);
        __transfer(arbitrationId, arb.bugId, objectBalances[arbitrationId]);
        _resolveBug(arb.bugId);
    }

    //getters
    function getProjectDetails(bytes32 projectId)
        external
        view
        returns(address owner, ProjectStatus status, uint256[5] memory rewards, uint256 totalPool) {
        Project memory p = projects[projectId];
        owner = p.owner;
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
        returns(address hunter, BugStatus status, Severity severity, uint256 timestamp) {
        Bug memory b = bugs[bugId];
        hunter = b.hunter;
        severity = b.severity;
        status = b.status;
        timestamp = b.timestamp;
    }

    function getLatestProposal(bytes32 bugId)
        external
        view
        returns(Severity severity, uint256 timestamp) {
        Proposal memory p = proposals[bugId][proposalCount[bugId]];
        timestamp = p.timestamp;
        severity = p.severity;
    }

    function getArbitrationDetails(bytes32 arbitrationId)
        external
        view
        returns(address plaintiff , address defendant, uint256 timestamp, uint256 commitPeriod, uint32 votersCount) {
        Arbitration memory a = arbitrations[arbitrationId];
        plaintiff = a.plaintiff;
        defendant = a.defendant;
        votersCount = a.votersCount;
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
