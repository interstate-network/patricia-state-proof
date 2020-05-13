pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "../MPT.sol";
import { TraversalRecordLib as TRL } from "../utils/TraversalRecordLib.sol";
import { RLPAccountLib as Account } from "../type-encoders/RLPAccountLib.sol";

library StateProofLib {
  using Account for bytes;
  using Account for Account.Account;
  using TRL for TRL.TraversalRecord;
  // using Account for Account.RLPAccount;

  struct StateProof {
    bytes value;
    bytes proof;
  }

  struct StateUpdateProof {
    bytes newValue;
    bytes proof;
  }

  function proveAccountInState(bytes32 stateRoot, address accountAddress, bytes memory proof)
  internal pure returns (bool inState, Account.Account memory account) {
    bytes memory key = RLP.toCompact(uint256(accountAddress));
    (bool success, TRL.TraversalRecord memory tail) = MPT.verifyProof(stateRoot, key, proof);
    account = Account.decodeAccount(tail.getValue());
    inState = success;
  }

  function updateAccountBalance(
    bytes32 stateRoot, address accountAddress, bytes memory proof, uint256 balanceChange, bool addition
  ) internal pure returns (
    bool isEmpty,
    bool balanceOk,
    Account.Account memory account,
    bytes32 newStateRoot
  ) {
    bytes memory key = RLP.toCompact(uint256(accountAddress));
    // make sure the proof is valid, get the traversal record
    (bool inState, TRL.TraversalRecord memory tail) = MPT.verifyProof(stateRoot, key, proof);
    require(inState, "Invalid state proof.");
    // check if the account was empty
    bytes memory provedValue = tail.getValue();
    isEmpty = provedValue.length == 0;
    // decode the account (decoder will replace empty bytes with an empty account)
    account = Account.decodeAccount(provedValue);
    if (addition) {
      // for addition, we don't need any balance check
      balanceOk = true;
      account.balance += balanceChange;
    } else {
      // for subtraction, if there's an insufficient balance we don't need to calculate the new root
      balanceOk = account.balance >= balanceChange;
      if (!balanceOk) return (isEmpty, balanceOk, account, bytes32(0));
      account.balance -= balanceChange;
    }
    bytes memory encodedNewAccount = account.encodeAccount();
    newStateRoot = MPT.updateRoot(tail, encodedNewAccount);
  }

  function proveStorageValue(Account.Account memory account, bytes32 slot, bytes memory proof)
  internal pure returns (bool, bytes32) {
    bytes memory key = RLP.toCompact(uint256(slot));
    (bool success, TRL.TraversalRecord memory tail) = MPT.verifyProof(account.stateRoot, key, proof);
    if (!success) return (false, bytes32(0));
    bytes32 retrievedValue = RLP.decodePrefixedWord(tail.getValue());
    return (success, retrievedValue);
  }

  function updateStateRoot(Account.Account memory account, bytes32 slot, bytes32 _value, bytes memory proof)
  internal pure returns (bool inStorage, bytes32 newRoot, bytes32 oldValue) {
    bytes memory key = RLP.toCompact(uint256(slot));
    (bool isValid, TRL.TraversalRecord memory tail) = MPT.verifyProof(account.stateRoot, key, proof);
    oldValue = RLP.decodePrefixedWord(tail.getValue());
    bytes memory newValue = RLP.encodeWithPrefix(uint256(_value));
    newRoot = MPT.updateRoot(tail, newValue);
    inStorage = isValid;
  }
}