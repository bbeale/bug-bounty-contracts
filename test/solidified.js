const Bounty = artifacts.require("SolidifiedBugBounty");
const Dai = artifacts.require("MockDai");

contract("Solidified Bug Bounty", accounts => {
  let dai,
    bugBounty = {};

  beforeEach(async () => {
    //dai = await Dai.new();
  });

  it("Deploys Correctly", async () => {
    // bugBounty = await Bounty.new(dai.address);
    // let daiAddress = await bugBounty.dai.call();
    // assert.equal(daiAddress, dai.address, "Should have correct Dai address");
  });

  it("Deposit Dai correctly", async () => {
    // bugBounty = await Bounty.new(dai.address);
    // await dai.approve(bugBounty.address, 1000000, { from: accounts[0] });
    // bugBounty.deposit(1000000, { from: accounts[0] });
  });
});
