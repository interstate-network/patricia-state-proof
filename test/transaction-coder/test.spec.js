const Account = require('ethereumjs-account').default;
const { Transaction } = require('ethereumjs-tx');
const Web3 = require('web3');
const ganache = require('ganache-cli');
const path = require('path');
const { bufferToHex, bufferToInt, toBuffer } = require('ethereumjs-util');

const { expect } = require('chai');

const compile = require('../../utils/compile');
const { abi, evm: { bytecode: { object: bytecode } } } = compile(__dirname, 'Test', path.join(__dirname, '..', '..'))["Test.sol"].Test;

describe("SignedTransactionLib.sol", () => {
  let web3, contract, provider, from;
  let tx, encoded, stateRoot;
  let sigGasCost;

  before(async () => {
    provider = ganache.provider();
    web3 = new Web3(provider);
    contract = new web3.eth.Contract(abi);
    [from] = await web3.eth.getAccounts();
    contract = await contract.deploy({
      data: bytecode
    }).send({ from, gas: 5e6 });
    const common = {
      chainId: () => 2020,
      gteHardfork: () => true
    }
    tx = new Transaction({
      nonce: 10,
      gasLimit: 500,
      gasPrice: 50,
      to: `0x${'ab'.repeat(20)}`,
      value: 50000,
      data: '0xabbb'
    }, { common });
    const privateKey = toBuffer(`0x${'ab'.repeat(32)}`);
    tx.sign(privateKey);
    stateRoot = toBuffer(`0x${'cc'.repeat(32)}`);
    encoded = Buffer.concat([tx.serialize(), stateRoot]);
  });

  it('derives the correct message hash', async () => {
    const msgHash = await contract.methods.getMessageHash({
      ...tx,
      stateRoot,
      gas: tx.gasLimit,
      to: bufferToHex(tx.to)
    }).call();
    expect(msgHash.toLowerCase()).to.eq(bufferToHex(tx.hash(false)))
  });

  it('derives the correct v value', async () => {
    const v = await contract.methods.getSigV({
      ...tx,
      stateRoot,
      gas: tx.gasLimit,
      to: bufferToHex(tx.to)
    }).call();
    expect(+v).to.eq(27 + bufferToInt(tx.v) - (tx.getChainId() * 2 + 35));
  });

  it('recovers the sender address', async () => {
    const signer = await contract.methods.getSenderAddress({
      ...tx,
      stateRoot,
      gas: tx.gasLimit,
      to: bufferToHex(tx.to)
    }).call();
    expect(signer.toLowerCase()).to.eq(bufferToHex(tx.getSenderAddress()));
    ({ gasUsed: sigGasCost } = await contract.methods.getSenderAddress({
      ...tx,
      stateRoot,
      gas: tx.gasLimit,
      to: bufferToHex(tx.to)
    }).send({ from }));
  })

  it('encodes a transaction', async () => {
    const result = await contract.methods.encodeTransaction({
      ...tx,
      stateRoot,
      gas: tx.gasLimit,
      to: bufferToHex(tx.to)
    }).call();
    expect(result.toLowerCase()).to.eq(bufferToHex(tx.serialize()));
  });

  it('decodes a transaction', async () => {
    const result = await contract.methods.decodeTransaction(encoded).call();
    expect(+result.nonce).to.eq(bufferToInt(tx.nonce));
    expect(+result.gas).to.eq(bufferToInt(tx.gasLimit));
    expect(+result.gasPrice).to.eq(bufferToInt(tx.gasPrice));
    expect(result.to.toLowerCase()).to.eq(bufferToHex(tx.to));
    expect(result.data.toLowerCase()).to.eq(bufferToHex(tx.data));
    expect(+result.v).to.eq(bufferToInt(tx.v));
    expect(result.r.toLowerCase()).to.eq(bufferToHex(tx.r));
    expect(result.s.toLowerCase()).to.eq(bufferToHex(tx.s));
    expect(result.stateRoot.toLowerCase()).to.eq(bufferToHex(stateRoot));
  });

  it('encodes a transaction with some empty fields', async () => {
    tx.nonce = Buffer.from([]);
    tx.data = Buffer.from([]);
    const result = await contract.methods.encodeTransaction({
      ...tx,
      stateRoot,
      gas: tx.gasLimit,
      to: bufferToHex(tx.to)
    }).call();
    expect(result.toLowerCase()).to.eq(bufferToHex(tx.serialize()));
  });

  it('decodes a transaction with some empty fields', async () => {
    encoded = Buffer.concat([tx.serialize(), stateRoot]);
    const result = await contract.methods.decodeTransaction(encoded).call();
    expect(+result.nonce).to.eq(bufferToInt(tx.nonce));
    expect(+result.gas).to.eq(bufferToInt(tx.gasLimit));
    expect(+result.gasPrice).to.eq(bufferToInt(tx.gasPrice));
    expect(result.to.toLowerCase()).to.eq(bufferToHex(tx.to));
    expect(result.data.toLowerCase()).to.eq(bufferToHex(tx.data));
    expect(+result.v).to.eq(bufferToInt(tx.v));
    expect(result.r.toLowerCase()).to.eq(bufferToHex(tx.r));
    expect(result.s.toLowerCase()).to.eq(bufferToHex(tx.s));
    expect(result.stateRoot.toLowerCase()).to.eq(bufferToHex(stateRoot));
  });

  async function costBenchmark(_tx, size) {
    _tx.data = Buffer.from('ff'.repeat(size), 'hex');
    const baseCost = 30000 + ((size + 4) * 16);
    const data = Buffer.concat([_tx.serialize(), stateRoot]);
    const words = 1 + (data.length / 32);
    const baseMemGas = (words * 3) + (words**2 / 512);
    const gasOverEstimate = baseMemGas * 5;
    let receipt = await contract.methods.decodeTransaction(data).send({ from, gas: 6e6 });
    console.log(`BENCHMARK: ${size} bytes in data field`);
    console.log(`\tDecode Estimated Gas Cost: ${gasOverEstimate}`);
    console.log(`\tBase Memory Gas: ${baseMemGas}`)
    console.log(`\tDecode Gas Cost: ${receipt.gasUsed - baseCost}`);
    // tx.
    receipt = await contract.methods.encodeTransaction({
      ..._tx,
      stateRoot,
      gas: tx.gasLimit,
      to: bufferToHex(_tx.to)
    }).send({ from, gas: 6e6 });
    console.log(`\tEncode Gas Cost: ${receipt.gasUsed - baseCost}`);
  }

  it('gets cost benchmark', async () => {
    console.log(`\tGet Sender Address Gas Cost: ${sigGasCost}`);
    await costBenchmark(tx, 100);
    await costBenchmark(tx, 250);
    await costBenchmark(tx, 500);
    await costBenchmark(tx, 1000);
    await costBenchmark(tx, 2000);
    await costBenchmark(tx, 5000);
  });
});