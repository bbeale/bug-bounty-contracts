const BugBounty = artifacts.require("SolidifiedBugBounty");
const Dai = artifacts.require("MockDai");
const {
  BN,
  constants,
  expectEvent,
  ether,
  expectRevert
} = require("openzeppelin-test-helpers");

const distributeDai = async (addresses, daiContract) => {
  addresses.forEach(async add => {
    await daiContract.transfer(add, new BN("1000000000000000000000"), {
      from: addresses[0]
    });
  });
};

const depositDai = async (addresses, daiContract, bugBountyContract) => {
  for (const add of addresses) {
    const amount = new BN("10000000000000000000");
    await daiContract.approve(bugBountyContract.address, amount, { from: add });
    await bugBountyContract.deposit(amount, {
      from: add
    });
  }

  // addresses.forEach(async add => {
  //   const amount = new BN("10000000000000000000");
  //   await daiContract.approve(bugBountyContract.address, amount, { from: add });
  //   await bugBountyContract.deposit(amount, {
  //     from: add
  //   });
  // });
  // addresses.forEach(async add => {
  //   const amount = new BN("10000000000000000000");
  //   //await daiContract.approve(bugBountyContract.address, amount, { from: add });
  //   await bugBountyContract.deposit(amount, {
  //     from: add
  //   });
  // });
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
      const projectId = "1";
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
  }); //Context Posting and managing Projects
});
