const Bounty = artifacts.require("SolidifiedBugBounty");

contract("Solidified Bug Bounty", accounts => {
  it("Deploys", async () => {
    let bb = Bounty.new();
    console.log(bb.address);

    assert.isTrue(bb.address != 0x0);
  });
});
