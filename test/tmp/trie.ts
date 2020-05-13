import { addHexPrefix, toBuffer, bufferToHex, rlp, BN } from 'ethereumjs-util';
const Trie = require('merkle-patricia-tree');
import TrieNode from 'merkle-patricia-tree/trieNode';
import Account from 'ethereumjs-account';
import { matchingNibbleLength } from 'merkle-patricia-tree/util';
const promisify = require('util.promisify')

const emptyStorageRoot = toBuffer('0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421');

const ln = (v) => ((console.log(require('util').inspect(v, { colors: true, depth: 15 }))), v);

const proofLib = (trie) => ({
  get: (key) => promisify(trie.get.bind(trie))(toBuffer(key)),
  // new Promise((resolve, reject) => trie.get(toBuffer(key), (err, result) => err ? reject(err) : resolve(result))),
  put: (key, val) => promisify(trie.put.bind(trie))(toBuffer(key), toBuffer(val)),
  // new Promise((resolve, reject) => trie.put(toBuffer(key), toBuffer(val), (err, result) => err ? reject(err) : resolve(result))),
  findPath: (key) => promisify(trie.findPath.bind(trie))(toBuffer(key)).then(
    ( _, __, proof) => {
      console.log(proof)
      return proof.map((v) => v.serialize())
    }
  ),
  prove: async (key) => {
    try {
      const nibbles = TrieNode.stringToNibbles(toBuffer(key));
      const simpleProof = await proofLib(trie).findPath(key);
      // new Promise((resolve, reject) => trie.findPath(toBuffer(key), (err, _, __, proof) => err ? reject(err) : resolve(proof.map((v) => v.serialize()))));
      let divergentSearch, divergent, nibblesPassed = 0;
      let i = 0;
      for (; i < simpleProof.length; i++) {
        const node = new TrieNode(rlp.decode(simpleProof[i]));
        if (node.type === 'branch') {
          if (nibblesPassed === nibbles.length) {
            divergentSearch = {
              node,
              nibblesPassed,
              nibble: 0x10
            };
            break;
          }
          if (node.raw[nibbles[nibblesPassed]].length === 0) break; 
          nibblesPassed++;
        } else {
          if (matchingNibbleLength(nibbles.slice(nibblesPassed), node.key) !== node.key.length) break;
          nibblesPassed += node.key.length;
          if (nibblesPassed === nibbles.length) {
            if (!i) break;
            divergentSearch = {
              node: new TrieNode(rlp.decode(simpleProof[i - 1])),
              nibble: nibbles[nibblesPassed - node.key.length - 1],
              nibblesPassed: nibblesPassed - node.key.length - 1
            }
            break;
          }
        }
      }
      if (i === simpleProof.length) throw Error('node not found');
      if (divergentSearch) {
        if (divergentSearch.node.type === 'branch') {
          let count = 0, divergentNibble;
          for (let i = 0; i < 0x11; i++) {
            if (i !== divergentSearch.nibble && divergentSearch.node.raw[i].length !== 0) {
              count++;
              divergentNibble = i;
              if (count == 2) break;
            }
          }
          if (count === 1) {
            const raw = divergentSearch.node.raw[divergentNibble];
            if (!Array.isArray(raw)) {
              let extendPath = nibbles.slice(0, divergentSearch.nibblesPassed).concat(divergentNibble).map((v) => v.toString(16));
              if (extendPath.length & 0x1) extendPath.push('0');
              divergent = await new Promise(
                (resolve, reject) => trie.findPath(toBuffer(addHexPrefix(extendPath.join(''))), 
                (err, n, m, path) => err ? reject(err) : resolve(path[path.length - 1].serialize()))
              );
            }
          }
        }
      }
      return bufferToHex(Buffer.concat([ Buffer.from([ divergent ? 0xfe : 0xff ]), rlp.encode((divergent ? [ rlp.decode(divergent) ] : []).concat(simpleProof.filter((v) => v.length >= 0x20).map((v) => rlp.decode(v)))) ]));
    } catch (e) {
      const x = await promisify(trie.findPath.bind(trie))(toBuffer(key)).then(
        (_, __, path) => path.map((v) => v.raw)
      );
      return bufferToHex(
        Buffer.concat([
          Buffer.from([0xff]),
          x
        ])
      );
    }
  }
})



export class ProofTrie {
  public lib: any;
  constructor(public trie: any) {
    this.trie = trie;
    this.lib = proofLib(trie);
  }

  async getAccount(address: string): Promise<Account> {
    const val = await this.lib.get(address).catch(err => null);
    return new Account(val || undefined);
  }

  async getStorageProof(address: string, slot: BN): Promise<{
    account: Account,
    proof: any
  }> {
    const account = await this.getAccount(address);
    const keyBuf = slot.toArrayLike(Buffer, 'be', 32);
    let trie: any
    if (account.stateRoot.equals(emptyStorageRoot)) {
      trie = new Trie();
    } else {
      trie = this.trie.copy();
      trie.root = account.stateRoot;
      trie._checkpoints = [];
    }
    const proof = await this.lib.prove(keyBuf);
    return { account, proof }
  }
}

async function test() {
  const t = new ProofTrie(new Trie())
  await t.lib.put('a', 'b');
  const proof = await t.lib.prove('a')
  console.log(proof)
}

test()