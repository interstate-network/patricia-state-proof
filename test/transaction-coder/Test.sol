pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import {
  SignedTransactionLib as Transaction
} from "../../src/type-encoders/SignedTransactionLib.sol";

contract Test {
  function getSenderAddress(Transaction.SignedTransaction memory transaction)
  public pure returns (address signer) {
    return Transaction.getSenderAddress(transaction);
  }
  function getSigV(Transaction.SignedTransaction memory transaction)
  public pure returns (uint256) {
    return Transaction.getSigV(transaction);
  }

  function getMessageHash(Transaction.SignedTransaction memory transaction)
  public pure returns (bytes32) {
    return Transaction.getMessageHash(transaction);
  }

  function encodeTransaction(Transaction.SignedTransaction memory transaction)
  public pure returns (bytes memory) {
    return Transaction.encodeTransaction(transaction);
  }

  function decodeTransaction(bytes memory encoded)
  public pure returns (Transaction.SignedTransaction memory) {
    return Transaction.decodeTransaction(encoded);
  }
}