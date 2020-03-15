pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "../../src/proofs/StateProofLib.sol";

contract Test {
  function proveAccountInState(bytes32 stateRoot, address accountAddress, bytes memory proof)
  public pure returns (bool inState, Account.Account memory account) {
    return StateProofLib.proveAccountInState(stateRoot, accountAddress, proof);
  }

  function updateAccountBalance(
    bytes32 stateRoot, address accountAddress, bytes memory proof, uint256 balanceChange, bool addition
  ) public pure returns (
    bool isEmpty, bool balanceOk, Account.Account memory account, bytes32 newStateRoot
  ) {
    return StateProofLib.updateAccountBalance(stateRoot, accountAddress, proof, balanceChange, addition); 
  }

  function proveStorageValue(Account.Account memory account, bytes32 slot, bytes32 _value, bytes memory proof)
  public pure returns (bool) {
    return StateProofLib.proveStorageValue(account, slot, _value, proof);
  }
}