import Account from 'ethereumjs-account';
import crypto from 'crypto';
import { bufferToHex, toBuffer, rlp, keccak256 } from 'ethereumjs-util';
import fs from 'fs';
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
  endRoot?: string;
  populatedAddresses?: string[];
  proof0?: AccountInfo;
  proof1?: AccountInfo;
}

async function getNewAccountProof(trie: Trie, nonce: number): Promise<AccountInfo> {
  const address = randomHexString(20);
  const addressHash = toHex(keccak256(toBuffer(address)));
  const account = await trie.getAccount(address);
  const proof = await trie.getAccountProof(address);
  const root = toHex(trie.root);
  account.nonce = toBuffer(nonce);
  await trie.putAccount(address, account);
  return { address, addressHash, account, root, proof };
}

async function getProofInfo(populateWith: number = 0) {
  const trie = new Trie();
  let res: ProofInfo = {};
  res.populatedAddresses = [];
  res.trie = trie;
  for (let i = 0; i < populateWith; i++) {
    const { address } = await getNewAccountProof(trie, 1);
    res.populatedAddresses.push(address);
  }
  res.proof0 = await getNewAccountProof(trie, 1);
  res.proof1 = await getNewAccountProof(trie, 2);
  res.endRoot = toHex(trie.root);
  return res;
}

const debugPath = path.join(__dirname, 'dump');

function writeDebugOutput(
  accountInfo: AccountInfo,
  errMessage: string,
  i: number
) {
  if (!fs.existsSync(debugPath)) fs.mkdirSync(debugPath);
  const { account, root, proof, address, addressHash } = accountInfo;
  const accountJson = {
    nonce: toHex(account.nonce),
    balance: toHex(account.nonce),
    codeHash: toHex(account.codeHash),
    stateRoot: toHex(account.stateRoot)
  };
  const filePath = path.join(debugPath, `error-dump-${i}.json`);
  fs.writeFileSync(filePath, JSON.stringify({
    account: accountJson,
    root,
    proof,
    address,
    addressHash,
    errMessage
  }, null, 2));
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

  /**
   * There is an error in the MPT library where an invalid proof erroneously
   * gives a value for a different key.
   * In this test, we put in the first account and execute a proof, which correctly
   * validates the proof with `success=true`. However, when the second proof is executed,
   * it will still return `success=true`, but with an output value equal to the first account,
   * despite the value not being inserted yet.
   * This is not an error with the buffer references to the root or proofs, as they are cast to strings
   * immediately upon being formed.
   * To verify that this is the issue:
   * - there is an assertion that the addresses of the two proofs do not match
   * - there is an assertion that the account values do not match
   * - the nonces used for the accounts are different
   */
  function itShouldExecuteTest(i: number) {
    return describe(`Should run test ${i}`, async () => {
      describe('Less populated state', async () => {
        let proofInfo: ProofInfo;

      before(async () => {
        proofInfo = await getProofInfo();
        expect(proofInfo.proof0.address).to.not.eq(proofInfo.proof1.address);
        expect(proofInfo.proof0.proof).to.not.eq(proofInfo.proof1.proof);
        expect(proofInfo.proof0.root).to.not.eq(proofInfo.proof1.root);
        expect(
          toHex(proofInfo.proof0.account.serialize())
        ).to.not.eq(
          proofInfo.proof1.account.serialize()
        );
      });

      /* PASSES */
      it(`Always verifies the first proof`, async () => {
        const proven = await contract.methods.verifyProof(
          proofInfo.proof0.root,
          proofInfo.proof0.addressHash,
          proofInfo.proof0.proof
        ).call();
        expect(proven.success).to.eq(true);
        expect(proven.value).to.eq(null);
      });

      /* PASSES */
      it('Always erroneously validates the neighbor', async () => {
        const result1 = await contract.methods.verifyProof(
          proofInfo.proof1.root,
          proofInfo.proof1.addressHash,
          proofInfo.proof1.proof,
        ).call();
        expect(result1.success).to.eq(true);
        expect(result1.value).to.eq(
          toHex(proofInfo.proof0.account.serialize())
        );
      });

      /* FAILS - What should happen */
      it('Should prove an empty second account', async () => {
        const result1 = await contract.methods.verifyProof(
          proofInfo.proof1.root,
          proofInfo.proof1.addressHash,
          proofInfo.proof1.proof,
        ).call();
        expect(result1.success).to.eq(true);
        expect(result1.value).to.eq(null);
      });

      /* FAILS */
      it('Should update the state with the second account', async () => {
        const result = await contract.methods.updateRoot(
          proofInfo.proof1.root,
          proofInfo.proof1.addressHash,
          proofInfo.proof1.proof,
          proofInfo.proof1.account.serialize()
        ).call();
        expect(result.success).to.be.true;
        /* Commented because it validates the neighbor instead of the correct node. */
        // expect(result.oldValue).to.eq(null);
        expect(result.newStateRoot).to.eq(proofInfo.endRoot);
      });
      })

      /**
       * Whenever the proof function returns `success=true` and `value=neighbor`,
       * the updateRoot function also fails.
       * 
       * Even when the state is more populated, certain paths cause errors.
       * This test writes debug files when there is a failure on updateRoot.
       * 
       * I believe the error must be originating from one of these:
       * - the key nibbles somehow
       * - the encoding in the catch block for proof-lib
       * - the node type handling (lack of handling for VOID nodes in the updateRoot function probably
       *    responsible for first failure, but idk about afterwards)
       * 
       * The debug output includes an array of populated addresses - each of them
       * are made into new accounts with the only set value being nonce=0
      */
      describe('More populated state', async () => {
        let info: ProofInfo;
        before(async () => {
          info = await getProofInfo(i+1);
        });

        it('Sometimes fails to prove a value', async () => {
          const result1 = await contract.methods.verifyProof(
            info.proof1.root,
            info.proof1.addressHash,
            info.proof1.proof,
          ).call();
          expect(result1.success).to.eq(true);
          expect(result1.value).to.eq(null);
        });

        it('Sometimes fails to update a value', async () => {
          try {
            const result = await contract.methods.updateRoot(
              info.proof1.root,
              info.proof1.addressHash,
              info.proof1.proof,
              info.proof1.account.serialize()
            ).call()
            expect(result.success).to.be.true;
            expect(result.newStateRoot).to.eq(info.endRoot);
          } catch (err) {
            writeDebugOutput(info.proof1, err.message, i);
            throw err;
          }
          
        })
      });
    })
  }

  describe('Should look for any bad paths', async () => {
    // it
    for (let i = 0; i < 10; i++) itShouldExecuteTest(i);
  })
});