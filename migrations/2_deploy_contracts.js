// System contracts
const VatContract = artifacts.require("../contracts/Vat");
const BrokerContract = artifacts.require("../contracts/Broker");
const ExecContract = artifacts.require("../contracts/Exec");
const VaultContract = artifacts.require("../contracts/Vault");
const ProxyContract = artifacts.require("../contracts/Proxy");
const SpotterContract = artifacts.require("../contracts/Spotter");
const LiquidatorContract = artifacts.require("../contracts/Liquidator.sol");
const ZrxWrapperContract = artifacts.require("../contracts/ZrxExchangeWrapper");

// External contracts
const OracleContract = artifacts.require("../contracts/Oracle");
const TokenContract = artifacts.require("../contracts/ERC20Mintable");
const { 
  ZrxExchangeContract, 
  ZrxProxyContract 
} = require("../test/contracts/zrxV2");

// utils
const BigNum = require("bignumber.js");
const { assetDataUtils } = require('@0xproject/order-utils');

module.exports = async function(deployer, network, accounts) {
  const user = accounts[0];
  const peer = accounts[1];
  const owner = accounts[2];
  const mintAmt = web3.utils.toWei('100', 'ether');
  const price0 = web3.utils.toWei('100', 'ether');

  // Main contracts
  let vat = await VatContract.new({from:owner});
  let proxy = await ProxyContract.new({from:owner});
  let vault = await VaultContract.new(proxy.address, {from:owner});
  let exec = await ExecContract.new(vat.address, vault.address, {from:owner});
  let broker = await BrokerContract.new(vat.address, vault.address, {from:owner});
  let liquidator = await LiquidatorContract.new(vat.address, broker.address, {from:owner});

  // Oracle. This will ultimately be a MakerDAO medianizer contract or similar
  let oracle = await OracleContract.new(price0, true, {from:owner});

  // prepare zero ex contracts for deployment
  const sendDefaults = {from:owner, gas: 6721975, gasPrice: 100000000000}
  ZrxExchangeContract.setProvider(web3.currentProvider);
  ZrxExchangeContract.class_defaults = sendDefaults;
  ZrxProxyContract.setProvider(web3.currentProvider);
  ZrxProxyContract.class_defaults = sendDefaults;
    
  // Tokens
  let owedGem = await TokenContract.new({from:owner});
  let heldGem = await TokenContract.new({from:owner});
  let zrxGem = await TokenContract.new({from:owner});
  await owedGem.mint(user, web3.utils.toBN(mintAmt), {from:owner}); // mint due tokens
  await heldGem.mint(user, web3.utils.toBN(mintAmt), {from:owner}); // mint trade tokens
  await zrxGem.mint(user, web3.utils.toBN(mintAmt), {from:owner}); // mint zrx tokens
  await owedGem.mint(peer, web3.utils.toBN(mintAmt), {from:owner}); // mint due tokens
  await heldGem.mint(peer, web3.utils.toBN(mintAmt), {from:owner}); // mint trade tokens
  await zrxGem.mint(peer, web3.utils.toBN(mintAmt), {from:owner}); // mint zrx tokens

  // Zero Ex Exchange
  const zrxAssetData = assetDataUtils.encodeERC20AssetData(zrxGem.address);
  let zrxExchange = await ZrxExchangeContract.new(zrxAssetData, {from:owner});
  let zrxProxy = await ZrxProxyContract.new({from:owner});
  // register exchange and proxy with each other
  await zrxProxy.addAuthorizedAddress(zrxExchange.address, {from:owner});
  await zrxExchange.registerAssetProxy(zrxProxy.address, {from:owner});
    
  // Zero Ex Exchange Wrapper
  let wrapper = await ZrxWrapperContract.new(
    vault.address, 
    proxy.address,
    zrxExchange.address, 
    zrxProxy.address, 
    zrxGem.address, 
    {from:owner}
  );

  // The spotter. Takes the medianizer value for pair and pushes it into the Chief
  let pairKey = web3.utils.soliditySha3(
    {t:'address', v: owedGem.address}, 
    {t:'address', v:heldGem.address}
  );
  let spotter = await SpotterContract.new(broker.address, oracle.address, pairKey, {from:owner});

  // Authorize contracts to interact with each other
  vat.addAuth(exec.address, {from:owner});
  vat.addAuth(broker.address, {from:owner});
  vat.addAuth(liquidator.address, {from:owner});
  vault.addAuth(exec.address, {from:owner});
  vault.addAuth(broker.address, {from:owner});
  broker.addAuth(spotter.address, {from:owner});
  broker.file(web3.utils.toHex("wrapper"), wrapper.address, 1, {from:owner});
  proxy.addAuth(vault.address, {from:owner});
  proxy.addAuth(wrapper.address, {from:owner});
  wrapper.addAuth(broker.address, {from:owner});

  // approve trading pair
  exec.file(web3.utils.toHex("validTokenPair"), pairKey, 1, {from:owner});

}