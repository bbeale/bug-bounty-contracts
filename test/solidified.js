const BugBounty = artifacts.require("SolidifiedBugBounty");
const Dai = artifacts.require("MockDai");
const {
  BN,
  constants,
  expectEvent,
  expectRevert
} = require("openzeppelin-test-helpers");

const distributeDai = async (addresses, daiContract) => {
  addresses.forEach(async add => {
    await daiContract.transfer(add, new BN("1000000000000000000000"), {
      from: addresses[0]
    });
  });
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

  context("Contract Interactions", async () => {
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

    it("User can post contract", async () => {
      const ipfsHash = web3.utils.asciiToHex("Project Infor");
      let amount = new BN("1000000000000000000");
      await dai.approve(bugBounty.address, amount);
      await bugBounty.deposit(amount, { from: accounts[0] });
      await bugBounty.postProject(ipfsHash, new BN("500000000000000000"), [
        "30000",
        "20000",
        "10000",
        "5000",
        "1000"
      ]);
    });
  });
});
