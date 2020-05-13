const Account = require('ethereumjs-account').default;
const Web3 = require('web3');
const ganache = require('ganache-cli');
const path = require('path');
const { bufferToHex, bufferToInt } = require('ethereumjs-util');

const { expect } = require('chai');

const compile = require('../../utils/compile');
const { abi, evm: { bytecode: { object: bytecode } } } = compile(__dirname, 'Test', path.join(__dirname, '..', '..'))["Test.sol"].Test;

describe("RLPAccountLib.sol", () => {
  let web3, contract, provider, from;
  let account;

  before(async () => {
    provider = ganache.provider();
    web3 = new Web3(provider);
    contract = new web3.eth.Contract(abi);
    [from] = await web3.eth.getAccounts();
    contract = await contract.deploy({
      data: bytecode
    }).send({ from, gas: 5e6 });
    account = new Account({
      nonce: 2,
      balance: 500,
      stateRoot: '0x' + '05'.repeat(32),
      codeHash: '0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470'
    });
  });

  it('encodes an account', async () => {
    const result = await contract.methods.encodeAccount(account).call();
    expect(result).to.eql(bufferToHex(account.serialize()))
  });

  it('decodes an account', async () => {
    const result = await contract.methods.decodeAccount(account.serialize()).call();
    expect(+result.nonce).to.eq(bufferToInt(account.nonce));
    expect(+result.balance).to.eq(bufferToInt(account.balance));
    expect(result.stateRoot).to.eq(bufferToHex(account.stateRoot));
    expect(result.codeHash).to.eq(bufferToHex(account.codeHash));
  })
});