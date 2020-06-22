import Account from 'ethereumjs-account';
import crypto from 'crypto';
import { bufferToHex } from 'ethereumjs-util';
const Web3 = require('web3');
const ganache = require('ganache-cli');
import {
  StateTrie as Trie
} from '../../utils/trie';
const path = require('path');
const { expect } = require('chai')

function randomHexString(size) {
  const bytes = crypto.randomBytes(size);
  return '0x' + bytes.toString('hex');
}

const compile = require('../../utils/compile');
const { abi, evm: { bytecode: { object: bytecode } } } = compile(__dirname, 'Test', path.join(__dirname, '..', '..'))["Test.sol"].Test;

describe("StateProofLib.sol", () => {
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

  describe("Prove & Update Empty Account", async () => {
    let trie: Trie, account, key, encoded, proof, proof2, root, root2;

    before(async () => {
      trie = new Trie();
      root = bufferToHex(trie.root);
      key = randomHexString(20);
      proof = await trie.getAccountProof(key);
      account = new Account({
        nonce: 0,
        balance: 500,
      });
      await trie.putAccount(key, account);
      root2 = bufferToHex(trie.root);
    })

    it('Should prove an account exists in a patricia merkle trie', async () => {
      const result = await contract.methods.proveAccountInState(root, key, proof).call();
      expect(result.inState).to.eq(true);
      expect(+result.account.nonce).to.eq(0);
      expect(+result.account.balance).to.eq(0);
      const result2 = await contract.methods.updateAccountBalance(
        root, key, proof, 500, true
      ).call();
      expect(result2.isEmpty).to.eq(true);
      expect(result2.balanceOk).to.eq(true);
      expect(result2.newStateRoot).to.eq(root2)
    });
  })

});
