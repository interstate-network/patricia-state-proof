pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "../../src/MPT.sol";

contract Test {
  using SliceLib for *;
  using RLP for *;
  using TraversalRecordLib for *;

  function calculateTrieKeyFromAddress(address accountAddress) internal pure returns (bytes memory) {
    return abi.encodePacked(keccak256(abi.encodePacked(accountAddress)));
  }

  // function updateRoot(TraversalRecordLib.TraversalRecord memory record, bytes memory newValue)
  // public pure
  // returns (bytes32 outputRoot) {
  //   return MPT.updateRoot(record, newValue);
  // }

  function verifyProof(bytes32 root, bytes memory key, bytes memory proof)
  public pure
  returns (bool success, bytes memory value) {
    (bool _success, TraversalRecordLib.TraversalRecord memory tail) = MPT.verifyProof(root, key, proof);
    return (_success, tail.getValue());
  }


  function verifyProof2(bytes32 root, bytes memory key, bytes memory proof)
  public pure
  returns (bool success, TraversalRecordLib.TraversalRecord memory tail) {
    return MPT.verifyProof(root, key, proof);
  }

  function updateRoot(bytes32 root, bytes memory key, bytes memory proof, bytes memory value)
  public pure
  returns (bool success, bytes memory oldValue, bytes32 newStateRoot) {
    (bool _success, TraversalRecordLib.TraversalRecord memory tail) = MPT.verifyProof(root, key, proof);
    success = _success;
    oldValue = tail.getValue();
    newStateRoot = MPT.updateRoot(tail, value);
  }

  function getSelector(bytes memory proof)
  public pure
  returns (RLP.Walker memory) {
    return RLP.fromRlp(proof.toSlice(1)).enterList();
  }

  function getProgress(bytes memory key, bytes memory proof)
  public pure
  returns (MPT.ProgressState) {
    RLP.Walker memory selector = RLP.fromRlp(proof.toSlice(1)).enterList();
    bytes memory nibbles = MPT.toNibbles(key.toSlice(), 0);
    TraversalRecordLib.TraversalRecord memory current = uint256(0x0).toRecord();
    MPT.ProgressState state = MPT.ProgressState.CONTINUE;
    return MPT.Progress({
      nibbles: nibbles,
      selector: selector,
      current: current,
      state: state
    }).state;
  }

  function getNibbles(bytes memory key) public pure returns (bytes memory) {
    return MPT.toNibbles(key.toSlice(), 0);
  }

  function getTraversalRecord()
  public pure returns (TraversalRecordLib.TraversalRecord memory) {
    return uint256(0x0).toRecord();
  }

  // RLP.Walker memory selector = RLP.fromRlp(proof.toSlice(1)).enterList();
}