import Account from 'ethereumjs-account';
import crypto from 'crypto';
import { bufferToHex, bufferToInt } from 'ethereumjs-util';
const Web3 = require('web3');
const ganache = require('ganache-cli');
import {
  StateTrie as Trie,
  StorageTrie
} from '../../utils/trie';
// const Trie = require('merkle-patricia-tree');
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

  describe("proveAccountInState", async () => {
    let trie: Trie, account, key, encoded, proof, root;
    before(async () => {
      trie = new Trie();
      account = new Account({
        nonce: 2,
        balance: 500,
        stateRoot: Buffer.alloc(32, 5, 'hex')
      });
      key = randomHexString(20);
      await trie.putAccount(key, account);
      /* Put some random elements in the trie */
      for (let i = 0; i < 100; i++) {
        const _key = randomHexString(32);
        const val = randomHexString(32);
        await trie.put(_key, val)
        // await lib.put(trie, _key, val)
      }
      proof = await trie.getAccountProof(key);
      root = bufferToHex(trie.root);
    })

    it('Should prove an account exists in a patricia merkle trie', async () => {
      const result = await contract.methods.proveAccountInState(root, key, proof).call();
      expect(result.inState).to.eq(true);
      expect(+result.account.nonce).to.eq(bufferToInt(account.nonce));
      expect(+result.account.balance).to.eq(bufferToInt(account.balance));
      expect(result.account.stateRoot).to.eq(bufferToHex(account.stateRoot));
      expect(result.account.codeHash).to.eq(bufferToHex(account.codeHash));
    });
  
    it('Should fail to prove an account that does not exist in the trie', async () => {
      const randKey = randomHexString(20)
      const result = await contract.methods.proveAccountInState(root, randKey, proof).call();
      expect(result.inState).to.eq(false);
    });
  })

  describe("updateAccountBalance", async () => {
    let trie: Trie, account, key, encoded, proof, root;
    before(async () => {
      trie = new Trie();
      account = new Account({
        nonce: 2,
        balance: 500,
        stateRoot: Buffer.alloc(32, 5, 'hex')
      });
      // encoded = account.serialize();
      key = randomHexString(20);
      await trie.putAccount(key, account)
      // await lib.put(trie, key, bufferToHex(encoded));
      /* Put some random elements in the trie */
      for (let i = 0; i < 100; i++) {
        const _key = randomHexString(32);
        const val = randomHexString(32);
        await trie.put(_key, val)
      }
      root = bufferToHex(trie.root);
      proof = await trie.getAccountProof(key);
    });

    it('Should increase an account balance and calculate the new root', async () => {
      const result = await contract.methods.updateAccountBalance(root, key, proof, 250, true).call();
      expect(result.isEmpty).to.eq(false);
      expect(result.balanceOk).to.eq(true);
      expect(result.account.balance).to.eq('750');
      const newAccount = new Account({
        nonce: 2,
        balance: 750,
        stateRoot: Buffer.alloc(32, 5, 'hex')
      });
      await trie.putAccount(key, newAccount);
      // await lib.put(trie, key, bufferToHex(newAccount.serialize()));
      // (await lib.prove(trie, key));
      const newRoot = bufferToHex(trie.root);
      expect(result.newStateRoot).to.eq(newRoot);
    });

    it('Should decrease an account balance and calculate the new root', async () => {
      const result = await contract.methods.updateAccountBalance(root, key, proof, 250, false).call();
      expect(result.isEmpty).to.eq(false);
      expect(result.balanceOk).to.eq(true);
      expect(result.account.balance).to.eq('250');
      const newAccount = new Account({
        nonce: 2,
        balance: 250,
        stateRoot: Buffer.alloc(32, 5, 'hex')
      });
      await trie.putAccount(key, newAccount);
      // await lib.put(trie, key, bufferToHex(newAccount.serialize()));
      // (await lib.prove(trie, key));
      const newRoot = bufferToHex(trie.root);
      expect(result.newStateRoot).to.eq(newRoot);
    });

    it('Should recognize if an account has an insufficient balance', async () => {
      const result = await contract.methods.updateAccountBalance(root, key, proof, 600, false).call();
      expect(result.isEmpty).to.eq(false);
      expect(result.balanceOk).to.eq(false);
    });
  });

  describe("proveStorageValue", async () => {
    let trie: StorageTrie, account, key, val, encoded, proof, root;
    before(async () => {
      trie = new StorageTrie();
      key = randomHexString(32);
      val = 150;
      await trie.put(key, val);
      /* Put some random elements in the trie */
      for (let i = 0; i < 100; i++) {
        const _key = randomHexString(32);
        const val = randomHexString(32);
        await trie.put(_key, val)
      }
      root = bufferToHex(trie.trie.root);
      proof = await trie.prove(key)
      account = new Account({
        nonce: 5,
        balance: 250,
        stateRoot: root,
        codeHash: randomHexString(32)
      })
    });

    it('Should prove a value at a storage slot', async () => {
      const valHex = ['0x', '00'.repeat(31), '96'].join('')
      const result = await contract.methods.proveStorageValue(Object.assign(account, { storageRoot: account.stateRoot }), key, valHex, proof).call();
      expect(result).to.eq(true);
    })
  })

  describe('updateStorageRoot', () => {
    let trie, account, key, val, encoded, proof, root;
    before(async () => {
      trie = new StorageTrie();
      key = randomHexString(32);
      val = 150;
      await trie.put(key, val);
      /* Put some random elements in the trie */
      for (let i = 0; i < 100; i++) {
        const _key = randomHexString(32);
        const val = randomHexString(32);
        await trie.put(_key, val)
      }
      root = bufferToHex(trie.root);
      proof = await trie.prove(key);
      account = {
        nonce: 5,
        balance: 250,
        stateRoot: root,
        codeHash: randomHexString(32)
      }
    });

    it('Should update a value at a storage slot', async () => {
      const valHex = ['0x', '00'.repeat(31), '96'].join('');
      const newValHex = ['0x', '00'.repeat(31), '95'].join('');
      const result = await contract.methods.updateStorageRoot(Object.assign(account, { storageRoot: root }), key, newValHex, proof).call();
      expect(result.oldValue).to.eq(valHex);
      expect(result.inStorage).to.eq(true);
      await trie.put(key, 149);
      // await t.prove(trie, key);
      const newRoot = bufferToHex(trie.root);
      expect(result.newRoot).to.eq(newRoot);
    })
  })
});
