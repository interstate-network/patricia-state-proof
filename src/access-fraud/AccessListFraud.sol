pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import { MessageWitnessLib as Message } from "../access/MessageWitnessLib.sol";
import { AccessRecordLib as Access } from "../access/AccessRecordLib.sol";
import { StateProofLib as State } from "../proofs/StateProofLib.sol";
import { RLPAccountLib as Account } from "../type-encoders/RLPAccountLib.sol";

contract AccessListFraud {
  function proveBalanceFraud(
    Message.MessageWitness memory messageWitness,
    bytes memory proof,
    uint256 recordIndex
  ) public pure returns (bool) {
    bytes memory encoded = messageWitness.access_list[recordIndex];
    uint256 opcode;
    // make sure the record is for a balance operation
    assembly { opcode := mload(add(encoded, 0x20)) }
    require(opcode == 0x31, "Record not for a balance operation.");
    // decode the record
    Access.BalanceWitness memory record = Access.toBalanceWitness(encoded);
    // get the state root prior to the operation
    bytes32 stateRoot = Message.getLastState(messageWitness, recordIndex);
    // verify the provided state proof
    (bool inState, Account.Account memory account) = State.proveAccountInState(stateRoot, record.target, proof);
    require(inState, "Invalid state proof provided.");
    if (account.balance != record.value) return true;
  }


}