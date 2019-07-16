const BugBounty = artifacts.require("SolidifiedBugBounty");
const SolidifiedProxy = artifacts.require("SolidifiedProxy");
const Dai = artifacts.require("MockDai");

module.exports = function(deployer) {
  // deployer
  //   .deploy(Dai)
  //   .then(instance => {
  //     return deployer.deploy(BugBounty, instance.address);
  //   })
  //   .then(instance => {
  //     return deployer.deploy(SolidifiedProxy, instance.address);
  //   });
};
