const BugBounty = artifacts.require("SolidifiedBugBounty");
const Dai = artifacts.require("MockDai");
const {
  BN,
  constants,
  expectEvent,
  time,
  ether,
  expectRevert
} = require("openzeppelin-test-helpers");

const distributeDai = async (addresses, daiContract) => {
  addresses.forEach(async add => {
    await daiContract.transfer(add, ether("10000"), {
      from: addresses[0]
    });
  });
};

const depositDai = async (addresses, daiContract, bugBountyContract) => {
  for (const add of addresses) {
    const amount = ether("5000");
    await daiContract.approve(bugBountyContract.address, amount, { from: add });
    await bugBountyContract.deposit(amount, {
      from: add
    });
  }
};

contract("Solidified Bug Bounty", accounts => {
  let dai,
    bugBounty = {};

  beforeEach(async () => {
    dai = await Dai.new();
  });

  context("Deployment", async () => {
    it("Deploys Correctly", async () => {
      bugBounty = await BugBounty.new(dai.address);
      let daiAddress = await bugBounty.dai.call();
      assert.equal(daiAddress, dai.address, "Should have correct Dai address");
    });
  });

  context("Depositing and Withdrawing tokens", async () => {
    beforeEach(async () => {
      bugBounty = await BugBounty.new(dai.address);
      await distributeDai(accounts, dai);
    });

    it("Deposit Dai correctly", async () => {
      let amount = new BN("1000000000000000000");
      await dai.approve(bugBounty.address, amount);
      await bugBounty.deposit(amount, { from: accounts[0] });
      let balance = await bugBounty.balances.call(accounts[0]);
      assert.isTrue(balance.eq(amount));
    });

    it("Fails for user that haven't approved the Dai contract", async () => {
      await expectRevert.unspecified(
        bugBounty.deposit(1000000, { from: accounts[1] })
      );
    });

    it("Withdraw Dai correctly", async () => {
      let amount = new BN("1000000000000000000");
      await dai.approve(bugBounty.address, amount, { from: accounts[2] });
      let balanceTokenBefore = await dai.balanceOf(accounts[2]);
      await bugBounty.deposit(amount, { from: accounts[2] });
      await bugBounty.withdraw(amount, { from: accounts[2] });
      let balanceBug = await bugBounty.balances.call(accounts[2]);
      let balanceTokenAfter = await dai.balanceOf(accounts[2]);
      assert.isTrue(balanceTokenBefore.eq(balanceTokenAfter));
      assert.isTrue(balanceBug.isZero());
    });

    it("Fails withdawr if user has no balance Dai contract", async () => {
      await expectRevert.unspecified(
        bugBounty.withdraw(1000000, { from: accounts[1] })
      );
    });
  }); //Context deposit and withdrawing tokens

  context("Posting and Managing Projects", async () => {
    beforeEach(async () => {
      bugBounty = await BugBounty.new(dai.address);
      await distributeDai(accounts, dai);
      await depositDai(accounts, dai, bugBounty);
    });

    it("User can post contract", async () => {
      const projectId = web3.utils.soliditySha3(
        { t: "address", v: accounts[3] },
        { t: "uint256", v: 1 }
      );
      //const projectId = "1";
      const totalPool = ether("5");
      const ipfsHash = web3.utils.asciiToHex("Project Info");
      const rewards = [
        ether("3"),
        ether("2"),
        ether("1"),
        ether("0.5"),
        ether("0.1")
      ];
      await bugBounty.postProject(ipfsHash, totalPool, rewards, {
        from: accounts[3]
      });
      let project = await bugBounty.getProjectDetails.call(projectId);
      assert.equal(project[0], accounts[3]);
      assert.isTrue(project[2].isZero());
      for (var i = 0; i < rewards.length; i++) {
        assert.isTrue(project[3][i].eq(rewards[i]));
      }
      assert.isTrue(project[4].eq(totalPool));
    });

    it("Revert projects with unordered arrays", async () => {
      const totalPool = ether("5");
      const ipfsHash = web3.utils.asciiToHex("Project Info");
      const rewards = [
        ether("0.1"),
        ether("3"),
        ether("2"),
        ether("1"),
        ether("0.5")
      ];
      await expectRevert(
        bugBounty.postProject(ipfsHash, totalPool, rewards, {
          from: accounts[3]
        }),
        "Rewards must be ordered"
      );
    });

    it("Revert if pool is to small", async () => {
      const totalPool = ether("3");
      const ipfsHash = web3.utils.asciiToHex("Project Info");
      const rewards = [
        ether("5"),
        ether("3"),
        ether("2"),
        ether("1"),
        ether("0.5")
      ];
      await expectRevert(
        bugBounty.postProject(ipfsHash, totalPool, rewards, {
          from: accounts[3]
        }),
        "totalPool should be greater than critical reward"
      );
    });

    it("User can pull posted contracts", async () => {
      const projectId = web3.utils.soliditySha3(
        { t: "address", v: accounts[4] },
        { t: "uint256", v: 1 }
      );

      const totalPool = ether("5");
      const ipfsHash = web3.utils.asciiToHex("Project Info");
      const rewards = [
        ether("3"),
        ether("2"),
        ether("1"),
        ether("0.5"),
        ether("0.1")
      ];
      await bugBounty.postProject(ipfsHash, totalPool, rewards, {
        from: accounts[4]
      });

      await bugBounty.pullProject(projectId, {
        from: accounts[4]
      });

      let project = await bugBounty.getProjectDetails.call(projectId);
      assert.equal(project[0], accounts[4]);
      assert.isTrue(project[2].eq(new BN("2")));
    });

    it("It fails when non-owner pulls contract", async () => {
      const projectId = web3.utils.soliditySha3(
        { t: "address", v: accounts[4] },
        { t: "uint256", v: 1 }
      );
      const totalPool = ether("5");
      const ipfsHash = web3.utils.asciiToHex("Project Info");
      const rewards = [
        ether("3"),
        ether("2"),
        ether("1"),
        ether("0.5"),
        ether("0.1")
      ];
      await bugBounty.postProject(ipfsHash, totalPool, rewards, {
        from: accounts[4]
      });

      await expectRevert(
        bugBounty.pullProject(projectId, {
          from: accounts[1]
        }),
        "Not authorized"
      );
    });

    it("Owner can can increase project pool", async () => {
      const projectId = web3.utils.soliditySha3(
        { t: "address", v: accounts[4] },
        { t: "uint256", v: 1 }
      );
      const totalPool = ether("5");
      const ipfsHash = web3.utils.asciiToHex("Project Info");
      const rewards = [
        ether("3"),
        ether("2"),
        ether("1"),
        ether("0.5"),
        ether("0.1")
      ];
      await bugBounty.postProject(ipfsHash, totalPool, rewards, {
        from: accounts[4]
      });

      let project = await bugBounty.getProjectDetails.call(projectId);
      const initialPool = project[4];
      await bugBounty.increasePool(projectId, totalPool, {
        from: accounts[4]
      });
      project = await bugBounty.getProjectDetails.call(projectId);
      const finalPool = project[4];
      assert.isTrue(initialPool.add(totalPool).eq(finalPool));
    });
  }); //Context Posting and managing Projects

  context("Posting Bugs", async () => {
    const totalPool = ether("5");
    const ipfsHash = web3.utils.asciiToHex("Project Info");
    const rewards = [
      ether("3"),
      ether("2"),
      ether("1"),
      ether("0.5"),
      ether("0.1")
    ];
    const projectOwner = accounts[1];
    const projectId = web3.utils.soliditySha3(
      { t: "address", v: projectOwner },
      { t: "uint256", v: 1 }
    );
    const bugId = web3.utils.soliditySha3(
      { t: "bytes32", v: projectId },
      { t: "uint256", v: 0 }
    );
    beforeEach(async () => {
      bugBounty = await BugBounty.new(dai.address);
      await distributeDai(accounts, dai);
      await depositDai(accounts, dai, bugBounty);

      await bugBounty.postProject(ipfsHash, totalPool, rewards, {
        from: projectOwner
      });
    });

    it("Hunter can submit bug", async () => {
      const bugInfo = web3.utils.asciiToHex("Bug Info");
      const severity = new BN("2");
      const bugValue = rewards[severity.toNumber()];
      const hunter = accounts[5];

      let previousBalance = await bugBounty.balances.call(hunter);
      await bugBounty.postBug(bugInfo, projectId, severity, { from: hunter });
      let finalBalance = await bugBounty.balances.call(hunter);
      let bug = await bugBounty.getBugDetails.call(bugId);
      assert.equal(bug[0], hunter);
      assert.isTrue(bug[2].isZero());
      assert.isTrue(bug[3].eq(bugValue));
      assert.isTrue(
        previousBalance.eq(finalBalance.add(bugValue.div(new BN("10"))))
      );
    });

    it("Project owner can accept bug", async () => {
      const bugInfo = web3.utils.asciiToHex("Bug Info");
      const severity = new BN("0");
      const bugValue = rewards[severity.toNumber()];
      const hunter = accounts[5];

      let previousBalance = await bugBounty.balances.call(hunter);
      await bugBounty.postBug(bugInfo, projectId, severity, { from: hunter });
      await bugBounty.acceptBug(projectId, bugId, { from: projectOwner });

      let finalBalance = await bugBounty.balances.call(hunter);
      let bug = await bugBounty.getBugDetails.call(bugId);
      let project = await bugBounty.getProjectDetails(projectId);
      assert.equal(bug[0], hunter);
      assert.isTrue(bug[2].eq(new BN("1")));
      assert.isTrue(previousBalance.eq(finalBalance.sub(bugValue)));
      assert.isTrue(project[2].eq(new BN("1")));
      assert.isTrue(project[4].eq(totalPool.sub(bugValue)));
    });

    it("Bug can accept if timeout has passed", async () => {
      const bugInfo = web3.utils.asciiToHex("Bug Info");
      const severity = new BN("0");
      const bugValue = rewards[severity.toNumber()];
      const hunter = accounts[5];

      let previousBalance = await bugBounty.balances.call(hunter);
      await bugBounty.postBug(bugInfo, projectId, severity, { from: hunter });
      await time.increase(time.duration.days(4));
      await bugBounty.timeoutAcceptBug(projectId, bugId);

      let finalBalance = await bugBounty.balances.call(hunter);
      let bug = await bugBounty.getBugDetails.call(bugId);
      let project = await bugBounty.getProjectDetails(projectId);
      assert.equal(bug[0], hunter);
      assert.isTrue(bug[2].eq(new BN("1")));
      assert.isTrue(previousBalance.eq(finalBalance.sub(bugValue)));
      assert.isTrue(project[2].eq(new BN("1")));
      assert.isTrue(project[4].eq(totalPool.sub(bugValue)));
    });

    it("Owner can make counter proposal", async () => {
      const bugInfo = web3.utils.asciiToHex("Bug Info");
      const justification = web3.utils.asciiToHex("Justification");
      const severity = new BN("0");
      const newSeverity = new BN("2");
      const bugValue = rewards[severity.toNumber()];
      const hunter = accounts[5];
      await bugBounty.postBug(bugInfo, projectId, severity, { from: hunter });
      await bugBounty.rejectBug(projectId, bugId, justification, newSeverity, {
        from: projectOwner
      });

      let proposal = await bugBounty.getLatestProposal.call(bugId);
      let bug = await bugBounty.getBugDetails.call(bugId);
      assert.equal(proposal[0], projectOwner);
      assert.isTrue(bug[2].eq(new BN("3")));
    });

    it("Hunter can accept owner proposal", async () => {
      const bugInfo = web3.utils.asciiToHex("Bug Info");
      const justification = web3.utils.asciiToHex("Justification");
      const severity = new BN("0");
      const newSeverity = new BN("2");
      const bugValue = rewards[newSeverity.toNumber()];
      const hunter = accounts[5];
      let previousBalance = await bugBounty.balances.call(hunter);
      await bugBounty.postBug(bugInfo, projectId, severity, { from: hunter });
      await bugBounty.rejectBug(projectId, bugId, justification, newSeverity, {
        from: projectOwner
      });
      await bugBounty.acceptProposal(projectId, bugId, { from: hunter });
      let finalBalance = await bugBounty.balances.call(hunter);
      let proposal = await bugBounty.getLatestProposal.call(bugId);
      let bug = await bugBounty.getBugDetails.call(bugId);
      let project = await bugBounty.getProjectDetails(projectId);
      assert.equal(proposal[0], projectOwner);
      assert.isTrue(bug[2].eq(new BN("1")));
      assert.isTrue(previousBalance.eq(finalBalance.sub(bugValue)));
      assert.isTrue(project[4].eq(totalPool.sub(bugValue)));
    });

    it("Hunter can make counter proposal", async () => {
      const bugInfo = web3.utils.asciiToHex("Bug Info");
      const justification = web3.utils.asciiToHex("Justification");
      const counterJust = web3.utils.asciiToHex("Counter Justification");
      const severity = new BN("0");
      const newSeverity = new BN("2");
      const finalSeverity = new BN("1");
      const hunter = accounts[5];
      await bugBounty.postBug(bugInfo, projectId, severity, { from: hunter });
      await bugBounty.rejectBug(projectId, bugId, justification, newSeverity, {
        from: projectOwner
      });
      await bugBounty.counterProposal(
        projectId,
        bugId,
        counterJust,
        finalSeverity,
        { from: hunter }
      );
      let proposal = await bugBounty.getLatestProposal.call(bugId);
      let bug = await bugBounty.getBugDetails.call(bugId);
      assert.equal(proposal[0], hunter);
      assert.isTrue(bug[2].eq(new BN("3")));
    });
  }); //Context Posting Bugs

  context("Arbitration", async () => {
    const totalPool = ether("5");
    const ipfsHash = web3.utils.asciiToHex("Project Info");
    const rewards = [
      ether("3"),
      ether("2"),
      ether("1"),
      ether("0.5"),
      ether("0.1")
    ];

    const projectOwner = accounts[1];
    const hunter = accounts[2];
    const projectId = web3.utils.soliditySha3(
      { t: "address", v: projectOwner },
      { t: "uint256", v: 1 }
    );
    const bugId = web3.utils.soliditySha3(
      { t: "bytes32", v: projectId },
      { t: "uint256", v: 0 }
    );
    const arbitrationId = web3.utils.soliditySha3(
      { t: "bytes32", v: projectId },
      { t: "bytes32", v: bugId }
    );
    const bugInfo = web3.utils.asciiToHex("Bug Info");
    const severity = new BN("2");
    const newSeverity = new BN("2");
    const justification = web3.utils.asciiToHex("Justification");
    const counterJust = web3.utils.asciiToHex("Counter Justification");
    const finalSeverity = new BN("1");

    beforeEach(async () => {
      bugBounty = await BugBounty.new(dai.address);
      await distributeDai(accounts, dai);
      await depositDai(accounts, dai, bugBounty);

      await bugBounty.postProject(ipfsHash, totalPool, rewards, {
        from: projectOwner
      });
      await bugBounty.postBug(bugInfo, projectId, severity, { from: hunter });

      await bugBounty.rejectBug(projectId, bugId, justification, newSeverity, {
        from: projectOwner
      });

      await bugBounty.counterProposal(
        projectId,
        bugId,
        counterJust,
        finalSeverity,
        { from: hunter }
      );
    });

    //Check if arbitrations is created correctly
    it("Any party can send to arbitration", async () => {
      const plaintiff = projectOwner;
      const defendant = hunter;
      await bugBounty.sendToArbitration(projectId, bugId, { from: plaintiff });

      const arb = await bugBounty.getArbitrationDetails(arbitrationId);
      assert.equal(arb[0], plaintiff);
      assert.equal(arb[1], defendant);
    });

    //reject arbitration
    it("Defendant party can reject arbitration", async () => {
      const plaintiff = projectOwner;
      const defendant = hunter;
      await bugBounty.sendToArbitration(projectId, bugId, { from: plaintiff });
      await bugBounty.rejectArbitration(arbitrationId, { from: defendant });

      const arb = await bugBounty.getArbitrationDetails(arbitrationId);
      let bug = await bugBounty.getBugDetails.call(bugId);
      assert.isTrue(bug[2].eq(new BN("2")));
      assert.equal(arb[0], plaintiff);
      assert.equal(arb[1], defendant);
    });

    //timeout reject
    it("Anyone can reject arbitration if timeout has passed", async () => {
      const plaintiff = projectOwner;
      const defendant = hunter;
      await bugBounty.sendToArbitration(projectId, bugId, { from: plaintiff });
      await time.increase(time.duration.days("4"));
      await bugBounty.rejectArbitration(arbitrationId);

      let bug = await bugBounty.getBugDetails.call(bugId);
      assert.isTrue(bug[2].eq(new BN("2")));
    });

    //accept arbitration
    it("Defendant can accept arbitration", async () => {
      const plaintiff = projectOwner;
      const defendant = hunter;
      await bugBounty.sendToArbitration(projectId, bugId, { from: plaintiff });
      await bugBounty.acceptArbitration(arbitrationId, { from: defendant });

      const arb = await bugBounty.getArbitrationDetails(arbitrationId);
      assert.equal(arb[0], plaintiff);
      assert.equal(arb[1], defendant);
    });
  }); //Context Arbitration

  context("Arbitration Voting", async () => {
    const totalPool = ether("5");
    const ipfsHash = web3.utils.asciiToHex("Project Info");
    const rewards = [
      ether("3"),
      ether("2"),
      ether("1"),
      ether("0.5"),
      ether("0.1")
    ];

    const projectOwner = accounts[1];
    const hunter = accounts[2];
    const projectId = web3.utils.soliditySha3(
      { t: "address", v: projectOwner },
      { t: "uint256", v: 1 }
    );
    const bugId = web3.utils.soliditySha3(
      { t: "bytes32", v: projectId },
      { t: "uint256", v: 0 }
    );
    const arbitrationId = web3.utils.soliditySha3(
      { t: "bytes32", v: projectId },
      { t: "bytes32", v: bugId }
    );
    const bugInfo = web3.utils.asciiToHex("Bug Info");
    const severity = new BN("2");
    const newSeverity = new BN("2");
    const justification = web3.utils.asciiToHex("Justification");
    const counterJust = web3.utils.asciiToHex("Counter Justification");
    const finalSeverity = new BN("1");
    const plaintiff = projectOwner;
    const defendant = hunter;
    const votingFee = new BN(ether("10"));

    beforeEach(async () => {
      bugBounty = await BugBounty.new(dai.address);
      await distributeDai(accounts, dai);
      await depositDai(accounts, dai, bugBounty);

      await bugBounty.postProject(ipfsHash, totalPool, rewards, {
        from: projectOwner
      });
      await bugBounty.postBug(bugInfo, projectId, severity, { from: hunter });

      await bugBounty.rejectBug(projectId, bugId, justification, newSeverity, {
        from: projectOwner
      });

      await bugBounty.counterProposal(
        projectId,
        bugId,
        counterJust,
        finalSeverity,
        { from: hunter }
      );

      await bugBounty.sendToArbitration(projectId, bugId, { from: plaintiff });
      await bugBounty.acceptArbitration(arbitrationId, { from: defendant });
    });

    //vote on arbitration
    it("Third party can vote on arbitration", async () => {
      const voter = accounts[5];

      const vote = web3.utils.soliditySha3(
        { t: "uint256", v: "1" },
        { t: "bytes32", v: "666" }
      );
      await bugBounty.commitVote(arbitrationId, vote, { from: voter });
    });

    it("Anyone can slash a commit if reveald porematurely", async () => {
      const voter = accounts[5];
      const salt = web3.utils.asciiToHex("666");
      const vote = web3.utils.soliditySha3(
        { t: "uint256", v: "1" },
        { t: "bytes32", v: salt }
      );
      const slasher = accounts[8];
      let beforeBal = await bugBounty.balances.call(slasher);
      await bugBounty.commitVote(arbitrationId, vote, { from: voter });
      await bugBounty.slashCommit(arbitrationId, "1", salt, voter, {
        from: slasher
      });
      let afterBal = await bugBounty.balances.call(slasher);
      assert.isTrue(beforeBal.eq(afterBal.sub(votingFee)));
    });

    it("Voter can reveal at correct time", async () => {
      const voter = accounts[5];

      const salt = web3.utils.asciiToHex("666");
      const vote = web3.utils.soliditySha3(
        { t: "uint256", v: "1" },
        { t: "bytes32", v: salt }
      );
      let rep = await bugBounty.reputation.call(voter);
      await bugBounty.commitVote(arbitrationId, vote, { from: voter });
      await time.increase(time.duration.days("4"));
      await bugBounty.revealCommit(arbitrationId, "1", salt, {
        from: voter
      });
      let vot = await bugBounty.votes.call(arbitrationId, voter);
      assert.isTrue(vot.eq(new BN("1")));
    });
  }); //Context Voting
});
