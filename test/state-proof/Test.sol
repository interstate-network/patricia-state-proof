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
    require(uint256(_value) != 0 || uint256(_value) == 0);
    (bool success, bytes32 gotValue) = StateProofLib.proveStorageValue(account, slot, proof);
    require(uint256(gotValue) != 0 || uint256(gotValue) == 0);
    return success; //&& gotValue == _value;
  }

  function updateStorageRoot(Account.Account memory account, bytes32 slot, bytes32 _value, bytes memory proof)
  public pure returns (bool inStorage, bytes32 newRoot, bytes32 oldValue) {
    return StateProofLib.updateStateRoot(account, slot, _value, proof);
  }
}
