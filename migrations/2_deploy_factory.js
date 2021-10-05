const { soliditySha3 } = require("web3-utils");
const Factory = artifacts.require("UniswapV2Factory");
const Pair = artifacts.require("UniswapV2Pair");

module.exports = async(deployer, network, accounts) => {
  await deployer.deploy(Factory, accounts[0]);
  const factory = await Factory.deployed();
  const INIT_CODE_HASH = soliditySha3(Pair.bytecode);
  console.log(`INIT_CODE_HASH: ${INIT_CODE_HASH}`);
  console.log(`accounts[0]: ${accounts[0]}`);
  console.log(`feeToSetter: ${await factory.feeToSetter()}`);
  // await factory.setFeeTo(accounts[0]);
};
