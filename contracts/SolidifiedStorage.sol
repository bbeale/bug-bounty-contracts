pragma solidity 0.5.0;


import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";
import "../node_modules/openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

contract SolidifiedStorage {

    enum Severity { Critical, Major, Medium, Minor, Note, NoBug}
    enum BugStatus { pending, accepted, rejected, negotiation, arbitration}
    enum ProjectStatus {active, unfunded, closed}
    enum Ruling {noVote, plaintiff, defendant}

    struct Project {
        address owner;
        ProjectStatus status;
        mapping(uint256 => uint256) rewards;
    }

    struct Bug {
        address hunter;
        BugStatus status;
        Severity severity;
        uint32 timestamp;
        bytes32 projectId;
    }

    struct Proposal {
        Severity severity;
        uint32 timestamp;
    }

    struct Arbitration {
        address plaintiff;
        address defendant;
        uint32 votersCount;
        uint32 commitPeriod;
        uint32 requestTime;
        bytes32 bugId;
    }

    mapping(address => uint256) public reputation;
    mapping(address => uint256) public balances;
    mapping(bytes32 => uint256) public objectBalances;

    mapping(bytes32 => Project) public projects;
    mapping(bytes32 => Bug) public bugs;
    mapping(bytes32 => Arbitration) public arbitrations;
    mapping(bytes32 => mapping(uint256 => Proposal)) public proposals;

    mapping(bytes32 => uint256) public bugCount;
    mapping(bytes32 => uint256) public proposalCount;
    uint256 internal projectCount;

    mapping(bytes32 => mapping(address => bytes32)) public commits;
    mapping(bytes32 => mapping(address => Ruling)) public votes;
    mapping(bytes32 => address[5]) public voters;

    address public dai;
    bool initialized;
    uint256 constant public INTERIM = 3 days;
    uint256 constant public ARBITRATION_FEE = 10 ether;
    uint256 constant public VOTING_FEE = 10 ether;
    uint256 constant public BUG_STAKE = 10;
    uint256 constant public MINIMUN_QUORUM = 5;


    event Deposit(address holder, uint256 amount);
    event Withdraw(address holder, uint256 amount);
    event ProjectPosted(bytes32 Id, uint256 projectNumber, address indexed Owner, bytes32 ipfsInfo, uint256 totalPool);
    event ProjectPulled(bytes32 Id, address indexed Owner, uint256 time);
    event PoolIncreased(bytes32 Id, address indexed Owner,uint256 totalPool);
    event BugPosted(bytes32 projectId, bytes32 bugId, uint256 bugNumber, bytes32 bugInfo, address hunter, uint256 time);
    event BugAccepted(bytes32 projectId, bytes32 bugId, address hunter, address indexed sender);
    event BugRejected(bytes32 projectId, bytes32 bugId, address hunter, address indexed sender);
    event ProposalMade(bytes32 projectId, bytes32 bugId, bytes32 justification, uint256 proposalNumber, address proposer);
    event ArbitrationRequested(bytes32 projectId, bytes32 bugId, bytes32 arbitrationId, address indexed  plaintiff, address indexed defendant, uint256 time);
    event ArbitrationAccepted(bytes32 projectId, bytes32 bugId, bytes32 arbitrationId, address  indexed plaintiff, address  indexed defendant, uint256 time);
    event ArbitrationRejected(bytes32 projectId, bytes32 bugId, bytes32 arbitrationId, address  indexed plaintiff, address  indexed defendant, uint256 time);

}
