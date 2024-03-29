pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

library MessageWitnessLib {
  struct MessageWitness {
    bytes32 stateRootEnter;
    bytes32 stateRootLeave;
    bool isStatic;
    address origin;
    address caller;
    address to;
    address context;
    uint256 value;
    uint256 gasPrice;
    uint256 gasAvailable;
    uint256 gasUsed;
    uint256 gasRefund;
    bytes[] access_list;
    uint256 status;
    bytes32 returndataHash;
    bytes callData;
  }

  function witnessHash(MessageWitness memory witness) internal pure returns (bytes32 _hash) {
    _hash = keccak256(abi.encode(witness));
  }

  function fromBytes(bytes memory data)
  internal pure returns (MessageWitness memory retval) {
    (retval) = abi.decode(data, (MessageWitness));
  }

  function compareMeta(
    MessageWitness memory witness,
    bytes32 stateRootLeave,
    bool isStatic,
    address origin,
    uint256 gasPrice,
    address caller,
    address to,
    address context,
    bool success,
    uint256 value,
    bytes32 calldataHash,
    bytes memory returnData
  ) internal pure returns (bool) {
    bool staticMatch = witness.isStatic == isStatic;
    bool cdMatch = keccak256(witness.callData) == calldataHash;
    bool rdMatch = witness.returndataHash == keccak256(returnData);
    bool txMatch = witness.origin == origin && witness.gasPrice == gasPrice;
    bool addrMatch = witness.caller == caller && witness.to == to && witness.context == context;
    bool stateMatch = witness.stateRootLeave == stateRootLeave;
    bool valueMatch = witness.value == value;
    uint256 status = witness.status;
    bool statusMatch = (status == uint256(0) || status == uint256(2)) ? !success : success;
    return staticMatch && cdMatch && rdMatch && txMatch && addrMatch && stateMatch && valueMatch && statusMatch;
  }

  function getCallCountBefore(MessageWitness memory messageWitness, uint256 before) internal pure returns (uint256 count) {
    uint256 bodyPtr;
    assembly {
      bodyPtr := add(mload(add(messageWitness, 0x160)), 0x20)
      for { let i := 0 } lt(i, before) { i := add(i, 1) } {
        let bPtr := mload(add(bodyPtr, mul(i, 0x20))) // get pointer to next bytes
        let op := mload(add(bPtr, 0x20))
        if or(
          or(eq(op, 0xf1), eq(op, 0xf2)),
          or(eq(op, 0xf4), eq(op, 0xfa))
        ) { count := add(count, 1) }
      }
    }
  }

  /**
   * @dev getLastState
   * @notice Returns the state root prior to an access record. Begins at the record
   * immediately prior to a given index and works backwards until it finds a state-changing
   * operation, or if there are no previous state-changing operations, the stateRootEnter of
   * the message.
   */
  function getLastState(MessageWitness memory witness, uint256 recordIndex)
  internal pure returns (bytes32 stateRoot) {
    require(witness.access_list.length > recordIndex, "Record not in witness.");
    if (recordIndex == 0) stateRoot = witness.stateRootEnter;
    else {
      bool done = false;
      uint256 i = recordIndex - 1;
      while(!done) {
        bytes memory record = witness.access_list[i--];
        uint256 opcode;
        // the opcode is always the first word in a record
        assembly { opcode := mload(add(record, 0x20)) }
        if (opcode == 0xf4 || opcode == 0xf1 || opcode == 0xf2 || opcode == 0x55) {
          // the stateRoot is always the second word in a state-changing record
          assembly { stateRoot := mload(add(record, 0x40)) }
          done = true;
        }
        else if (i == 0) {
          stateRoot = witness.stateRootEnter;
          done = true;
        }
      }
    }
  }
}
