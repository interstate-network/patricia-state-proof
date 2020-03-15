pragma solidity ^0.6.0;

import "./SliceLib.sol";
import "./RLP.sol";

library TraversalRecordLib {
  using SliceLib for *;
  using RLP for *;
  enum NodeType {
    VOID,
    LEAF,
    EXTENSION,
    BRANCH
  }
  struct TraversalRecord {
    NodeType typeCode;
    uint256 indexOfTarget;
    SliceLib.Slice entireNode;
    SliceLib.Slice targetData;
    SliceLib.Slice nibblesAtNode;
    bytes nibblesPartial;
    uint256 parent;
    uint256 child;
    uint256 divergentNibble;
    uint256 divergent;
    uint256 nibblesPassed;
    uint256 nodesFromNull;
    bool isEmbedded;
  }
  function toPtr(TraversalRecord memory record) internal pure returns (uint256 ptr) {
    assembly {
      ptr := record
    }
  }
  function toRecord(uint256 ptr) internal pure returns (TraversalRecord memory record) {
    assembly {
      record := ptr
    }
  }
  function getRoot(TraversalRecord memory record) internal pure returns (bytes32) {
    while (record.parent != 0) {
      record = toRecord(record.parent);
    }
    return record.entireNode.toKeccak();
  }
  function toFields(SliceLib.Slice memory slice) internal pure returns (RLP.RLPItem[] memory) {
    return RLP.fromRlp(slice).enterList().readList();
  }
  function lastNonEmbedded(TraversalRecord memory record) internal pure returns (TraversalRecord memory retval) {
    retval = record;
    while (retval.isEmbedded) {
      retval = toRecord(retval.parent);
    }
  }
  function getValueAsSlice(TraversalRecord memory record) internal pure returns (SliceLib.Slice memory) {
    if (record.nodesFromNull != 0) return new bytes(0).toSlice();
    return record.targetData;
  }
  function getValue(TraversalRecord memory record) internal pure returns (bytes memory) {
    // return getValueAsSlice(record).copy();
    return record.targetData.copy();
  }
  function getNibbles(TraversalRecord memory record) internal pure returns (bytes memory) {
    return record.nibblesAtNode.getTargetData();
  }
}
