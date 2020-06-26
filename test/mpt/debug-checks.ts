import Account from 'ethereumjs-account';
import crypto from 'crypto';
import { bufferToHex, toBuffer, rlp, keccak256 } from 'ethereumjs-util';

import path from 'path';
import chai from 'chai';
import chaiAsPromised from "chai-as-promised";
const Web3 = require('web3');
const ganache = require('ganache-cli');
import { StateTrie as Trie } from '../../utils/trie';
import { toHex } from '../../utils/to';

const compile = require('../../utils/compile');
const {
  abi, evm: { bytecode: { object: bytecode } }
} = compile(__dirname, 'Test', path.join(__dirname, '..', '..'))["Test.sol"].Test;

chai.use(chaiAsPromised);
const { expect } = chai;

// VM Exception while processing transaction: invalid opcode

function randomHexString(size) {
  const bytes = crypto.randomBytes(size);
  return '0x' + bytes.toString('hex');
}

type AccountInfo = {
  root: string;
  proof: string;
  address: string;
  addressHash: string;
  account: Account;
}

type ProofInfo = {
  trie?: Trie;
  account0?: AccountInfo;
  account1?: AccountInfo;
}

async function getProofInfo(initialize?: boolean) {
  const trie = new Trie();
  let res: ProofInfo = {};
  res.trie = trie;
  if (initialize) {
    const address = randomHexString(20);
    const addressHash = toHex(keccak256(toBuffer(address)));
    const account = await trie.getAccount(address);
    const proof = await trie.getAccountProof(address);
    const root = toHex(trie.root);
    account.nonce = toBuffer(1);
    await trie.putAccount(address, account);
    res.account0 = {
      address, addressHash, account, root, proof
    };
  }
  const address = randomHexString(20);
  const addressHash = toHex(keccak256(toBuffer(address)));
  const account = await trie.getAccount(address);
  const proof = await trie.getAccountProof(address);
  const root = toHex(trie.root);
  account.nonce = toBuffer(1);
  await trie.putAccount(address, account);
  res.account1 = {
    address, addressHash, account, root, proof
  };
  return res;
}

describe("MPT.sol", () => {
  let web3, contract, provider, from;

  before(async () => {
    provider = ganache.provider();
    web3 = new Web3(provider);
    contract = new web3.eth.Contract(abi);
    [from] = await web3.eth.getAccounts();
    contract = await contract.deploy({
      data: bytecode
    }).send({ from, gas: 5e6 });
    await new Promise(resolve => setTimeout(resolve, 500))
  });

  describe("MPT First Update Error Tests", async () => {
    let proofInfo: ProofInfo;

    before(async () => {
      proofInfo = await getProofInfo(true);
    });

    it('Should print an RLP selector', async () => {
      const selector = await contract.methods.getSelector(proofInfo.account0.proof).call();
      // console.log(selector)
    })

    it('Should print nibbles', async () => {
      const nibbles = await contract.methods.getNibbles(proofInfo.account0.addressHash).call();
      // console.log(nibbles)
    })

    it('Should print a traversal record', async () => {
      const record = await contract.methods.getTraversalRecord().call();
      // console.log(record)
    })

    it('Should print an MPT progress', async () => {
      const progress = await contract.methods.getProgress(
        proofInfo.account0.addressHash, proofInfo.account0.proof
      ).call();
      // console.log(progress)
    })

    it('Should verify a proof', async () => {
      const proven = await contract.methods.verifyProof(
        proofInfo.account0.root,
        proofInfo.account0.addressHash,
        proofInfo.account0.proof
      ).call();
      expect(proven.success).to.be.true;
      expect(proven.value).to.eq(null);
      /**
        @throws
        This fails if instead of returning the value with tail.getValue(),
        we try to return the actual traversal record.
        This is depsite the fact that the getTraversalRecord() function succeeds.
        I believe this indicates some kind of error in the pointers, where
        both the way that updateRoot uses the traversal record and the way that solc attempts
        to encode it cause an invalid opcode operation.
        This error does not need to be fixed for the ABI encoding of a response, as that will never
        be used, but it may point to the reason for the error in updateRoot.
      */
      expect(
        contract.methods.verifyProof2(
          proofInfo.account0.root,
          proofInfo.account0.addressHash,
          proofInfo.account0.proof
        ).call()
      ).to.eventually.be.rejectedWith('VM Exception while processing transaction: invalid opcode')
    })

    it('Should update the root', async () => {
      /**
        @throws
        This fails with an invalid opcode error.
      */
      const result = await contract.methods.updateRoot(
        proofInfo.account0.root,
        proofInfo.account0.addressHash,
        proofInfo.account0.proof,
        proofInfo.account0.account.serialize()
      ).call();
      expect(result.success).to.be.true;
      expect(result.oldValue).to.eq(null);
      expect(result.newStateRoot).to.eq(proofInfo.account1.root)
    })
  });
});