pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./utils/RLP.sol";
import "./utils/SliceLib.sol";
import "./utils/MemcpyLib.sol";
import "./utils/TraversalRecordLib.sol";

library MPT {
  using RLP for *;
  using TraversalRecordLib for *;
  using SliceLib for *;
  enum ProgressState {
    CONTINUE,
    EXIT_WITH_FAILURE,
    EXIT_WITH_SUCCESS
  }
  bytes1 constant INCLUDE_DIVERGENT_NODE = 0xfe;
  bytes32 constant EMPTY_ROOT = 0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421;
  function walkBackProduceHashFromNode(TraversalRecordLib.TraversalRecord memory record, SliceLib.Slice memory segment) internal pure returns (bytes32) {
    uint256 ptr = record.toPtr();
    RLP.RLPItem memory toInsert = RLP.RLPItem({
      data: segment.copy(),
      pass: false
    });
    if (segment.length != record.targetData.length) {
      while (ptr != 0) {
        RLP.RLPItem[] memory fields = record.entireNode.toContainer().toFields();
        fields[record.indexOfTarget] = toInsert;
        toInsert = RLP.encodeList(fields);
        ptr = record.parent;
        record = ptr.toRecord();
        if (toInsert.data.length >= 0x20) {
          if (record.targetData.length == 0x20) return walkBackProduceHash(ptr, keccak256(toInsert.data));
          else if (ptr == 0) return keccak256(toInsert.data);
          else toInsert = abi.encodePacked(keccak256(toInsert.data)).toRLPItem();
        }
      }
    } else {
      bytes32 dest = bytes32(record.targetData.data);
      bytes32 src = bytes32(segment.data);
      MemcpyLib.memcpy(dest, src, segment.length);
      record = record.lastNonEmbedded();
      return walkBackProduceHash(record.parent, record.entireNode.deriveContainerKeccak());
    }
  }
  function walkBackProduceHash(uint256 ptr, bytes32 toInsert) internal pure returns (bytes32 outputRoot) {
    outputRoot = toInsert;
    while (ptr != 0) {
      TraversalRecordLib.TraversalRecord memory record = ptr.toRecord();
      uint256 target = record.targetData.data;
      assembly {
        mstore(target, outputRoot)
      }
      outputRoot = record.entireNode.deriveContainerKeccak();
      ptr = record.parent;
      record = ptr.toRecord();
    }
  }
  function joinNibbles(SliceLib.Slice memory a, SliceLib.Slice memory b) internal pure returns (SliceLib.Slice memory) {
    bytes memory result = new bytes(a.length + b.length);
    uint256 i = 0;
    for (; i < a.length; i++) {
      result[i] = a.get(i);
    }
    for (i = 0; i < b.length; i++) {
      result[i + a.length] = b.get(i);
    }
    return result.toSlice();
  }
  function removeBranch(TraversalRecordLib.TraversalRecord memory record, uint256 divergentNibble) internal pure returns (bytes32) {
    TraversalRecordLib.TraversalRecord memory divergent = record.divergent.toRecord();
    RLP.RLPItem[] memory fields = divergent.typeCode == TraversalRecordLib.NodeType.BRANCH && divergent.indexOfTarget == 0x10 ? new RLP.RLPItem[](0) : divergent.entireNode.toContainer().toFields();
    RLP.RLPItem[] memory replacement = new RLP.RLPItem[](2);
    SliceLib.Slice memory path = new bytes(1).toSlice();
    path.set(0, uint8(divergentNibble));
    TraversalRecordLib.NodeType typeCode;
    if (fields.length == 0) {
      path = new bytes(0).toSlice();
      typeCode = TraversalRecordLib.NodeType.LEAF;
      replacement[1] = divergent.targetData.copy().toRLPItem();
    } else if (fields.length == 2) {
      (TraversalRecordLib.NodeType typeCodeFromEncoded, bytes memory nibbles) = fromEncodedPath(fields[0].data.toSlice());
      typeCode = typeCodeFromEncoded;
      path = joinNibbles(path, nibbles.toSlice());
      replacement[1] = fields[1];
    } else {
      typeCode = TraversalRecordLib.NodeType.EXTENSION;
      replacement[1] = maybeEmbed(divergent.entireNode.toContainer().copy().toRLPItem());
    }
    record = record.parent.toRecord();
    if (record.toPtr() != 0) {
      RLP.RLPItem[] memory parentFields = record.entireNode.toContainer().toFields();
      if (parentFields.length == 2) {
        (/* typeCode */, SliceLib.Slice memory nibbles) = fromEncodedPathToSlice(parentFields[0].data.toSlice());
        
        path = joinNibbles(nibbles, path);
        record = record.parent.toRecord();
      }
    }
    replacement[0] = toEncodedPath(typeCode, path).toRLPItem();
    if (record.toPtr() == 0x0) return keccak256(RLP.encodeList(replacement).data);
    return walkBackProduceHashFromNode(record, RLP.encodeList(replacement).data.toSlice());
  }
  function maybeEmbed(RLP.RLPItem memory input) internal pure returns (RLP.RLPItem memory output) {
    output = input.data.length >= 0x20 ? RLP.RLPItem({
      pass: false,
      data: abi.encodePacked(keccak256(input.data))
    }) : input;
  }
  function removeLeaf(TraversalRecordLib.TraversalRecord memory record) internal pure returns (bytes32) {
    if (record.typeCode == TraversalRecordLib.NodeType.LEAF) {
      if (record.parent == 0x0) return EMPTY_ROOT;
      TraversalRecordLib.TraversalRecord memory parentRecord = record.parent.toRecord();
      if (parentRecord.divergent == 0x0) return walkBackProduceHashFromNode(parentRecord, new bytes(0).toSlice());
      else removeBranch(parentRecord, ~parentRecord.divergentNibble);
    }
    if (record.divergent != 0x0) return removeBranch(record, ~record.divergentNibble);
    if (record.parent != 0x0) {
      TraversalRecordLib.TraversalRecord memory parentRecord = record.parent.toRecord();
      if (parentRecord.divergent != 0x0) return removeBranch(parentRecord, ~parentRecord.divergentNibble);
    }
    return walkBackProduceHashFromNode(record, new bytes(0).toSlice());
  }
  function findDivergentNibble(TraversalRecordLib.TraversalRecord memory record) internal pure returns (uint256 divergentNibble, SliceLib.Slice memory slice) {
    uint256 nibble = record.indexOfTarget;
    RLP.Walker memory siblingCounter = RLP.fromRlp(record.entireNode.toContainer()).enterList();
    uint256 count = 0;
    divergentNibble = uint256(~0);
    for (; siblingCounter.state != RLP.WalkerState.REACHED_END; siblingCounter.walk()) {
      if (siblingCounter.pointer.length != 0 && nibble != siblingCounter.index) {
        count++;
        divergentNibble = siblingCounter.index;
        if (count == 2) {
          divergentNibble = uint256(~0);
          break;
        }
        slice = siblingCounter.pointer.toSlice();
      }
    }
  }
  struct CreateBranchLocals {
    RLP.RLPItem[] toSegment;
    uint256 startIndex;
    uint256 branchIndex;
    SliceLib.Slice sharedPath;
    SliceLib.Slice existingRemainingPath;
    SliceLib.Slice newRemainingPath;
    RLP.RLPItem[] newLeaf;
    uint256 newValueNibble;
    RLP.RLPItem newNodeEncoded;
    uint256 existingValueNibble;
    RLP.RLPItem[] newBranch;
    RLP.RLPItem existingNodeEncoded;
    RLP.RLPItem segment;
    RLP.RLPItem[] newExtension;
  }
  function createBranch(TraversalRecordLib.TraversalRecord memory record, bytes memory newValue) internal pure returns (bytes32) {
    CreateBranchLocals memory locals;
    bytes memory keyNibbles = record.getNibbles();
    locals.toSegment = record.entireNode.toContainer().toFields();
    if (record.typeCode == TraversalRecordLib.NodeType.BRANCH) {
      if (keyNibbles.length == record.nibblesPassed && record.indexOfTarget == 0x10) {
        return walkBackProduceHashFromNode(record, newValue.toSlice());
      } else if (record.nodesFromNull == 0x1) {
        locals.newLeaf = new RLP.RLPItem[](2);
        locals.newLeaf[0] = toEncodedPath(TraversalRecordLib.NodeType.LEAF, keyNibbles.toSlice(record.nibblesPassed)).toRLPItem();
        locals.newLeaf[1] = newValue.toRLPItem();
        return walkBackProduceHashFromNode(record, maybeEmbed(RLP.encodeList(locals.newLeaf)).data.toSlice());
      }
    }
    (
      /* TraversalRecordLib.NodeType typeCode */,
      SliceLib.Slice memory encodedPath
    ) = fromEncodedPathToSlice(locals.toSegment[0].data.toSlice());
    locals.startIndex = record.nibblesPassed - encodedPath.length;
    for (
      locals.branchIndex = 0;
      (
        locals.branchIndex < encodedPath.length &&
        locals.startIndex + locals.branchIndex < keyNibbles.length
      );
      locals.branchIndex++
    ) {
      if (keyNibbles[locals.branchIndex + locals.startIndex] != encodedPath.get(locals.branchIndex)) break;
    }
    locals.sharedPath = encodedPath.toSlice(0, locals.branchIndex);
    locals.existingRemainingPath = encodedPath.toSlice(locals.branchIndex + 1);
    locals.newRemainingPath = keyNibbles.toSlice(locals.startIndex + locals.branchIndex + 1);
    locals.toSegment[0].data = toEncodedPath(TraversalRecordLib.NodeType.EXTENSION, locals.existingRemainingPath);
    locals.newLeaf = new RLP.RLPItem[](2);
    locals.newLeaf[0].data = toEncodedPath(TraversalRecordLib.NodeType.LEAF, locals.newRemainingPath);
    locals.newLeaf[1].data = newValue;
    locals.newValueNibble = locals.branchIndex + locals.startIndex + 1 == keyNibbles.length ? 0x10 : uint256(uint8(keyNibbles[locals.branchIndex + locals.startIndex]));
    locals.newNodeEncoded = locals.newValueNibble == 0x10 ? locals.newLeaf[1] : maybeEmbed(RLP.encodeList(locals.newLeaf));
    locals.existingValueNibble = uint256(locals.branchIndex + 1 >= encodedPath.length ? 0x10 : uint8(encodedPath.get(locals.branchIndex)));
    locals.newBranch = new RLP.RLPItem[](17);
    locals.existingNodeEncoded = (
      record.typeCode == TraversalRecordLib.NodeType.LEAF &&
      locals.existingValueNibble == 0x10
    ) ? locals.toSegment[1] : maybeEmbed(RLP.encodeList(locals.toSegment));
    locals.newBranch[locals.existingValueNibble] = locals.existingNodeEncoded;
    locals.newBranch[locals.newValueNibble] = locals.newNodeEncoded;
    locals.segment = RLP.encodeList(locals.newBranch);
    if (locals.sharedPath.length != 0) {
      locals.newExtension = new RLP.RLPItem[](2);
      locals.newExtension[0].data = toEncodedPath(TraversalRecordLib.NodeType.EXTENSION, locals.sharedPath);
      locals.newExtension[1] = maybeEmbed(locals.segment);
      locals.segment = RLP.encodeList(locals.newExtension);
    }
    if (record.parent == 0x0) return keccak256(locals.segment.data);
    return walkBackProduceHashFromNode(record.parent.toRecord(), maybeEmbed(locals.segment).data.toSlice());
  }
  struct Progress {
    bytes nibbles;
    RLP.Walker selector;
    TraversalRecordLib.TraversalRecord current;
    ProgressState state;
  }
  function walkBack(TraversalRecordLib.TraversalRecord memory record) internal pure returns (TraversalRecordLib.TraversalRecord memory) {
    while (record.parent != 0x0) {
      record = record.parent.toRecord();
    }
    return record;
  }
  function updateRoot(TraversalRecordLib.TraversalRecord memory record, bytes memory newValue) internal pure returns (bytes32 outputRoot) {
    if (keccak256(record.getValue()) == keccak256(newValue)) return walkBack(record).entireNode.deriveContainerKeccak();
    if (record.getValue().length != 0) {
      if (newValue.length != 0) return walkBackProduceHashFromNode(record, newValue.toSlice());
      return removeLeaf(record);
    } else return createBranch(record, newValue);
  }
  function verifyProof(bytes32 root, bytes memory key, bytes memory proof) internal pure
  returns (bool success, TraversalRecordLib.TraversalRecord memory tail) {
    RLP.Walker memory selector = RLP.fromRlp(proof.toSlice(1)).enterList();
    Progress memory progress = Progress({
      nibbles: toNibbles(key.toSlice(), 0),
      selector: selector,
      current: uint256(0x0).toRecord(),
      state: ProgressState.CONTINUE
    });
    TraversalRecordLib.TraversalRecord memory current;
    assembly {
      current := 0x0
    }
    progress.current = current;
    bytes memory optionalDivergentNode = new bytes(0);
    if (proof[0] == INCLUDE_DIVERGENT_NODE) {
      optionalDivergentNode = selector.readContainingBytes();
      selector.walk();
    }
    while (true) {
      if (progress.state == ProgressState.CONTINUE && selector.state == RLP.WalkerState.LIST_ENTRY) {
        enterProofNode(progress, selector.enterList(), false);
        TraversalRecordLib.TraversalRecord memory last = progress.current.lastNonEmbedded(); 
        if (last.parent == 0x0) {
          if (last.entireNode.deriveContainerKeccak() != root) return (false, progress.current);
        } else if (last.parent.toRecord().targetData.asWord() != last.entireNode.deriveContainerKeccak()) return (false, progress.current);
        selector.walk();
      } else if (progress.state == ProgressState.EXIT_WITH_FAILURE) {
        return (false, progress.current);
      } else {
        bool divergentCheck = traceDivergentNode(progress, optionalDivergentNode);
        if (!divergentCheck) return (false, progress.current);
        return (
          (progress.current.typeCode == TraversalRecordLib.NodeType.VOID
            ? root == EMPTY_ROOT
            : progress.current.typeCode == TraversalRecordLib.NodeType.LEAF
          ) || progress.current.nodesFromNull != 0, progress.current);
      }
    }
  }
  function traceDivergentNode(Progress memory progress, bytes memory optionalDivergentNode) internal pure returns (bool) {
    if (progress.current.nodesFromNull != 0) return true;
    TraversalRecordLib.TraversalRecord memory current = progress.current;
    if (current.parent == 0x0) return true;
    if (!(current.typeCode == TraversalRecordLib.NodeType.BRANCH && current.indexOfTarget == 0x10)) {
      current = current.parent.toRecord();
    }
    bytes memory nibbles = current.getNibbles();
    (uint256 divergentNibble, SliceLib.Slice memory slice) = findDivergentNibble(current);
    if (divergentNibble == uint256(~0)) return true;
    if (slice.length < 0x20) {
      optionalDivergentNode = slice.copy();
      return true;
    }
    else if (keccak256(optionalDivergentNode) != slice.asWord()) return false;
    bytes memory nibblesCopy = nibbles.toSlice().copy();
    nibblesCopy[current.nibblesPassed - 1] = bytes1(uint8(divergentNibble));
    Progress memory progressShadow = Progress({
      nibbles: nibblesCopy,
      current: current,
      state: ProgressState.CONTINUE,
      selector: RLP.fromRlp(new bytes(0))
    });
    uint256 child = current.child;
    enterProofNode(progressShadow, RLP.fromRlp(optionalDivergentNode).enterList(), false);
    if (progressShadow.state == ProgressState.EXIT_WITH_FAILURE) return false;
    current.child = child;
    current.divergent = progress.current.toPtr();
    current.divergentNibble = ~divergentNibble;
    return true;
  }
  function fromEncodedPathToSlice(SliceLib.Slice memory slice) internal pure returns (TraversalRecordLib.NodeType, SliceLib.Slice memory) {
    (TraversalRecordLib.NodeType typeCode, bytes memory nibbles) = fromEncodedPath(slice);
    return (typeCode, nibbles.toSlice());
  }
  function fromEncodedPath(SliceLib.Slice memory slice) internal pure returns (TraversalRecordLib.NodeType valueType, bytes memory pathNibbles) {
    uint8 firstByte = uint8(slice.get(0));
    if (firstByte & 0x20 != 0) valueType = TraversalRecordLib.NodeType.LEAF;
    else valueType = TraversalRecordLib.NodeType.EXTENSION;
    if (firstByte & 0x10 != 0) pathNibbles = toNibbles(slice.toSlice(0), 1);
    else pathNibbles = toNibbles(slice.toSlice(1), 0);
  }
  function toEncodedPath(TraversalRecordLib.NodeType valueType, SliceLib.Slice memory nibbles) internal pure returns (bytes memory) {
    bytes memory encoded = new bytes((nibbles.length / 2) + 1);
    encoded[0] = bytes1(uint8((valueType == TraversalRecordLib.NodeType.LEAF ? 0x20 : 0x0) | ((nibbles.length & 0x1) << 4)));
    uint256 nibble = 0;
    if (nibbles.length & 0x1 != 0x0) {
      encoded[0] |= nibbles.get(0);
      nibble++;
    }
    for (uint256 i = 1; i < encoded.length; i++) {
      encoded[i] = (nibbles.get(nibble) << 4) | nibbles.get(nibble + 1);
      nibble += 2;
    }
    return encoded;
  }
  function enterProofNode(Progress memory progress, RLP.Walker memory selector, bool isEmbedded) internal pure returns (bool) {
    TraversalRecordLib.TraversalRecord memory newRecord;
    newRecord.entireNode = selector.data;
    newRecord.parent = progress.current.toPtr();
    newRecord.isEmbedded = isEmbedded;
    if (newRecord.parent != 0x0) {
      if (progress.current.nodesFromNull != 0) newRecord.nodesFromNull = progress.current.nodesFromNull + 1;
      progress.current.child = newRecord.toPtr();
    }
    progress.current = newRecord;
    while (true) {
      if (selector.index != 2) {
        if (selector.state == RLP.WalkerState.REACHED_END) {
          progress.state = ProgressState.EXIT_WITH_FAILURE;
          return false;
        }
        selector.walk();
      } else {
        if (selector.state == RLP.WalkerState.REACHED_END) {
          selector.rewindToListStart();
          (TraversalRecordLib.NodeType valueType, bytes memory nibblesPartial) = fromEncodedPath(selector.pointer);      
          newRecord.nibblesPartial = nibblesPartial;
          selector.walk();
          if (valueType == TraversalRecordLib.NodeType.LEAF) return enterLeafNode(progress, selector);
          else return enterExtensionNode(progress, selector);
        } else {
          selector.rewindToListStart();
          return enterBranchNode(progress, selector);
        }
      }
    }
  }
  function enterBranchNode(Progress memory progress, RLP.Walker memory selector) internal pure returns (bool) {
    progress.current.typeCode = TraversalRecordLib.NodeType.BRANCH;
    progress.current.nibblesAtNode = progress.nibbles.toSlice(0, progress.current.parent.toRecord().nibblesPassed);
    uint256 nibblesPassedBefore = progress.current.parent == 0x0 ? 0x0 : progress.current.parent.toRecord().nibblesPassed;
    uint256 nibble = progress.nibbles.length == nibblesPassedBefore ? uint8(0x10) : uint8(progress.nibbles[nibblesPassedBefore]);
    uint256 sibling = 0;
    bool multipleSiblings = false;
    uint256 i = 0;
    for (i = 0; selector.index < nibble; i++) {
      if (selector.pointer.length != 0) {
        if (sibling != 0) multipleSiblings = true;
        sibling = i;
      }
      if (selector.state == RLP.WalkerState.REACHED_END) return false;
      selector.walk();
    }
    progress.current.indexOfTarget = nibble;
    progress.current.targetData = selector.pointer.toSlice();
    progress.current.nibblesPassed = nibblesPassedBefore + 1;
    if (progress.current.targetData.length == 0) {
      if (progress.current.nodesFromNull == 0) progress.current.nodesFromNull = 1;
      if (multipleSiblings) {
        progress.state = ProgressState.EXIT_WITH_SUCCESS;
        return true;
      } else {
        for (i = nibble; i < 0x11 && !multipleSiblings; i++) {
          selector.walk();
          if (selector.pointer.length != 0) {
            if (sibling != 0) multipleSiblings = true;
            sibling = i;
          }
        }
        if (multipleSiblings) {
          progress.state = ProgressState.EXIT_WITH_SUCCESS;
          return true;
        } else {
          nibble = progress.current.indexOfTarget = i;
          progress.current.indexOfTarget = uint256(nibble);
          progress.current.targetData = selector.pointer.toSlice();
        }
      }
    }
    if (selector.index == 0x10) progress.state = ProgressState.EXIT_WITH_SUCCESS;
    if (selector.state == RLP.WalkerState.LIST_ENTRY) return enterProofNode(progress, selector.enterList(), true);
    else return true;
  }
  function enterExtensionNode(Progress memory progress, RLP.Walker memory selector) internal pure returns (bool) {
    progress.current.typeCode = TraversalRecordLib.NodeType.EXTENSION;
    progress.current.indexOfTarget = 1;
    uint256 nibblesPassedBefore = progress.current.parent == 0x0 ? 0x0 : progress.current.parent.toRecord().nibblesPassed;
    progress.current.nibblesAtNode = progress.nibbles.toSlice(0, nibblesPassedBefore);
    progress.current.targetData = selector.pointer;
    if (progress.current.nodesFromNull == 0 && !compareSlice(progress.current.nibblesPartial.toSlice(), progress.nibbles.toSlice(nibblesPassedBefore))) {
      progress.current.nodesFromNull++;
    }
    progress.current.nibblesPassed = nibblesPassedBefore + progress.current.nibblesPartial.length;
    if (selector.state == RLP.WalkerState.WORD_ENTRY) return true;
    else if (selector.state == RLP.WalkerState.LIST_ENTRY) {
      return enterProofNode(progress, selector.enterList(), true);
    } else {
      progress.state = ProgressState.EXIT_WITH_FAILURE;
      return false;
    }
  }
  function enterLeafNode(Progress memory progress, RLP.Walker memory selector) internal pure returns (bool) {
    progress.current.typeCode = TraversalRecordLib.NodeType.LEAF;
    progress.current.indexOfTarget = 1;
    progress.current.nibblesAtNode = progress.nibbles.toSlice(0, progress.current.parent.toRecord().nibblesPassed);
    uint256 nibblesPassed = progress.current.parent == 0 ? 0 : progress.current.parent.toRecord().nibblesPassed;
    progress.current.targetData = selector.pointer;
    if (progress.current.nodesFromNull == 0 && !compareSlice(progress.current.nibblesPartial.toSlice(), progress.nibbles.toSlice(nibblesPassed))) {
      progress.current.nodesFromNull++;
    }
    progress.current.nibblesPassed = nibblesPassed + progress.current.nibblesPartial.length;
    return true;
  }
  function toNibbles(SliceLib.Slice memory slice, uint256 nibbleOffset) internal pure returns (bytes memory) {
    uint256 nibbleAmount = slice.length * 2 - nibbleOffset;
    bytes memory nibbles = new bytes(nibbleAmount);
    uint256 start = 0;
    if (nibbleOffset == 1) {
      nibbles[0] = byte(uint8(slice.get(0)) & 0xf);
      start = 1;
    }
    uint256 dataOffset = nibbleOffset == 0 ? 0 : 1;
    for (uint256 i = 0; i < (nibbleAmount - start) / 2; i++) {
      nibbles[start + i*2] = byte((uint8(slice.get(i + dataOffset) & bytes1(uint8(0xf0))) >> uint8(4)));
      nibbles[start + i*2 + 1] = byte(uint8(slice.get(i + dataOffset)) & uint8(0xf));
    }
    return nibbles;
  }
  function compareSlice(SliceLib.Slice memory slice, SliceLib.Slice memory container) internal pure returns (bool) {
    if (slice.length > container.length) return false;
    for (uint256 i = 0; i < slice.length; i++) {
      if (slice.get(i) != container.get(i)) return false;
    }
    return true;
  }
}
