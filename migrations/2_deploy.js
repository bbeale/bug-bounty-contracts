let SolidifiedBugBounty = artifacts.require("SolidifiedBugBounty");
let MockDai = artifacts.require("MockDai");

// for testing only, implments a token with faucet, mints tokens to deployer and creates an allowance for the print contract
// then it creates an institution, and gives access to it and prints a certificate
// you can print certificates directly
const deployContractsDevelopment = async (deployer, accounts) => {

  /* token */
  const dai = await deployer.deploy(MockDai)

  /* main */
  const main = await deployer.deploy(SolidifiedBugBounty, dai.address)
  
  await dai.approve(main.address,"1000000000000000000000000");
  await main.deposit("1000000000000000000000000");
  /* Mock Data for frontend dev */
  const bugBounty = await main.postProject("0x1fd54831f488a22b28398de0c567a3b064b937f54f81739ae9bd545967f3abab", "1000000000000000000000", ["500000000000000000000","200000000000000000000","100000000000000000000","50000000000000000000","10000000000000000000"])
  await main.postProject("0x2fd54831f488a22b28398de0c567a3b064b937f54f81739ae9bd545967f3abac", "1000000000000000000000", ["500000000000000000000","200000000000000000000","100000000000000000000","50000000000000000000","10000000000000000000"])
  await main.postProject("0x3fd54831f488a22b28398de0c567a3b064b937f54f81739ae9bd545967f3abad", "1000000000000000000000", ["500000000000000000000","200000000000000000000","100000000000000000000","50000000000000000000","10000000000000000000"])
  let tx = await main.postProject("0x4fd54831f488a22b28398de0c567a3b064b937f54f81739ae9bd545967f3abad", "1000000000000000000000", ["500000000000000000000","200000000000000000000","100000000000000000000","50000000000000000000","10000000000000000000"])
  let projectId = tx.receipt.logs[0].args[0]

  await main.postBug( "0x5fd54831f488a22b28398de0c567a3b064b937f54f81739ae9bd545967f3abad", projectId, 1)
  await main.postBug( "0x6fd54831f488a22b28398de0c567a3b064b937f54f81739ae9bd545967f3abad", projectId, 2)
}

const deployContracts = async (deployer, accounts) => {
  try {

    return true
  } catch (err) {
    console.log('### error deploying contracts', err)
  }
}


module.exports = (deployer, network, accounts) => {
  deployer.then(async () => {
      if (["development","rinkeby"].includes(deployer.network))
        await deployContractsDevelopment(deployer, accounts)
      else
        await deployContracts(deployer, accounts)
      console.log('### finished deploying contracts')
    })
    .catch(err => console.log('### error deploying contracts', err))
}