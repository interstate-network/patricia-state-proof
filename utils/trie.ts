import { toBuffer, rlp } from 'ethereumjs-util';
import Account from 'ethereumjs-account';
const Trie = require('merkle-patricia-tree/secure');

import { BufferLike, toBuf32, toHex } from './to';

const emptyStorageRoot = toBuffer('0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421');
const proofLib = require('./proof-lib');

export class TrieWrapper {
  public lib: any;
  public trie: any;
  constructor(trie?: any) {
    if (!trie) trie = new Trie()
    this.trie = trie;
    this.lib = proofLib(trie);
  }
  get root(): Buffer { return this.trie.root; }
  get = (key: BufferLike): Promise<Buffer> => this.lib.get(key);
  put = (key: BufferLike, val: BufferLike) => this.lib.put(key, val);
  del = (key: BufferLike): Promise<void> => this.lib.del(key);
  prove = (key: BufferLike): Promise<string> => this.lib.prove(key);
}

export class StorageTrie extends TrieWrapper {
  get = (key: BufferLike): Promise<Buffer> => this.lib.get(toBuf32(key));
  put = async (key: BufferLike, value: BufferLike): Promise<string> => {
    return await this.lib.put(toBuf32(key), rlp.encode(toBuffer(value)));
  }
  prove = (key: BufferLike): Promise<string> => this.lib.prove(toBuf32(key));
}

export class StateTrie extends TrieWrapper {
  async getAccount(address: BufferLike): Promise<Account> {
    const val = await this.lib.get(toBuffer(address)).catch((err: any) => null);
    return new Account(val || undefined);
  }

  async putAccount(address: BufferLike, account: Account) {
    await this.lib.put(toBuffer(address), account.serialize());
  }

  async getAccountProof(address: BufferLike): Promise<string> {
    return this.lib.prove(toBuffer(address));
  }

  async getAccountStorageTrie(address: BufferLike): Promise<StorageTrie> {
    const account = await this.getAccount(address);

    let trie: any
    if (account.stateRoot.equals(emptyStorageRoot)) {
      trie = new Trie();
    } else {
      trie = this.trie.copy();
      trie.root = account.stateRoot;
      trie._checkpoints = [];
    }
    return new StorageTrie(trie);
  }

  async getAccountStorageProof(address: BufferLike, key: BufferLike): Promise<{
    value: Buffer,
    proof: string
  }> {
    const trie = await this.getAccountStorageTrie(address);
    const value = await trie.get(key);
    const proof = await trie.prove(key);
    return { value, proof };
  }
}
