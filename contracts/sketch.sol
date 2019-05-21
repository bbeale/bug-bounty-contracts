pragma solidity 0.5.8;

contract SolidifiedSketch{

    enum Severity { Critical, Major, Medium, Minor, Note}
    enum BugStatus { pending, accepted, rejected, negotiation, arbitration}

    struct Project {
        address owner,
        bytes32 infoHash,
        uint256 Pool,
        uint256 CriticalValue,
        uint256 MajorValue,
        uint256 MediumValue,
        uint256 MinorValue,
        uint256 MediumValue,
        Bug[] bugs
    }

    struct Bug {
        address hunter,
        Severity severity,
    }

    address public Dai;
    mapping(address -> uint256) public balances;
    mapping(address -> mapping(uint256 -> Project)) public projects;
    mapping(uint -> mapping(uint256 -> Bug)) public bugs;

    constructor() {

    }


    /**
            Balance Functions
    **/
    function deposit() {}
    function withdraw()
    function sendTip() {}

    //Move funds between users and objetcs(Pool, Bug, Arbitration, etc)
    function sendToPool() {}
    function sendToBug() {}
    function sendToArbitration() {}

    /**
            Contract Posting Functions
    **/
    function postProject() {}
    function updateProject() {}
    function increasePool() {}
    function pullProject() {}
    
    /**
            Bug Functions
    **/
    function postBug() {}
    function acceptBug() {}
    function rejectBug(){}
    function timeoutAccept() {}

    /**
            Arbitration Functions
    **/
    function sendToArbitration() {}
    function commitVote() {}
    function revealVote(){}

    /**
            Administrartive Functions
    **/
    function upgrade() {}
    function changeFee() {}
    function flagBugAsRepetivie() {}




}

