pragma solidity 0.5.0;

contract SolidifiedSketch{

    enum Severity { Critical, Major, Medium, Minor, Note}
    enum BugStatus { pending, accepted, rejected, negotiation, arbitration}
    enum ProjectStatus {draft, active, unfunded, closed}

    struct Project {
        uint256 id;
        address owner;
        bytes32 infoHash;
        uint256 Pool;
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
    address public Dai;
    mapping(address => uint256) public balances;
    mapping(uint256 => Project) public projects; //Owner => Id => Project
    mapping(uint => mapping(uint256 => Bug)) public bugs; //ProjectId => BugId => Bug

    constructor() public {
            projectCount++;
    }


    /**
            Balance Functions
    **/
    function deposit() public {}
    function withdraw() public {}
    function sendTip() public {}

    //Move funds between users and objetcs(Pool, Bug, Arbitration, etc)
    function sendToPool() public {}
    function sendToBug() public {}

    /**
            Contract Posting Functions
    **/
    function postProject(bytes32 ipfsHash, uint256 totalPool) public {
        //Add hash to projects mapping
        projects[projectCount] = Project(projectCount, msg.sender, ipfsHash, totalPool);
        //discount from owner balance
        //emit event
        //increment project count
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
}

