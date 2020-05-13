pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

library AccessRecordLib {
  struct BalanceWitness { // 0x31
    uint256 opcode;
    address target;
    uint256 value;
  }

  function toBalanceWitness(bytes memory _encoded) internal pure returns(BalanceWitness memory witness) {
    return abi.decode((_encoded), (BalanceWitness));
  }

  struct ExtCodeSizeWitness { // 0x3b
    uint256 opcode;
    address target;
    uint256 value;
  }

  function toExtCodeSizeWitness(bytes memory _encoded) internal pure returns(ExtCodeSizeWitness memory witness) {
    return abi.decode((_encoded), (ExtCodeSizeWitness));
  }

  struct ExtCodeCopyWitness { // 0x3c
    uint256 opcode;
    address target;
    bool exists;
  }

  function toExtCodeCopyWitness(bytes memory _encoded) internal pure returns(ExtCodeCopyWitness memory witness) {
    return abi.decode((_encoded), (ExtCodeCopyWitness));
  }

  struct ExtCodeHashWitness { // 0x3f
    uint256 opcode;
    address target;
    bytes32 value;
  }

  function toExtCodeHashWitness(bytes memory _encoded) internal pure returns(ExtCodeHashWitness memory witness) {
    return abi.decode((_encoded), (ExtCodeHashWitness));
  }

  struct BlockHashWitness { // 0x40
    uint256 opcode;
    uint256 target;
    bytes32 value;
  }

  function toBlockHashWitness(bytes memory _encoded) internal pure returns(BlockHashWitness memory witness) {
    return abi.decode((_encoded), (BlockHashWitness));
  }

  struct CoinbaseWitness { // 0x41
    uint256 opcode;
    address value;
  }

  function toCoinbaseWitness(bytes memory _encoded) internal pure returns(CoinbaseWitness memory witness) {
    return abi.decode((_encoded), (CoinbaseWitness));
  }

  struct TimestampWitness { // 0x42
    uint256 opcode;
    uint256 value;
  }

  function toTimestampWitness(bytes memory _encoded) internal pure returns(TimestampWitness memory witness) {
    return abi.decode((_encoded), (TimestampWitness));
  }

  struct NumberWitness { // 0x43
    uint256 opcode;
    uint256 value;
  }

  function toNumberWitness(bytes memory _encoded) internal pure returns(NumberWitness memory witness) {
    return abi.decode((_encoded), (NumberWitness));
  }

  struct GaslimitWitness { // 0x45
    uint256 opcode;
    uint256 value;
  }

  function toGaslimitWitness(bytes memory _encoded) internal pure returns(GaslimitWitness memory witness) {
    return abi.decode((_encoded), (GaslimitWitness));
  }

  struct ChainidWitness { // 0x46
    uint256 opcode;
    uint256 value;
  }

  function toChainidWitness(bytes memory _encoded) internal pure returns(ChainidWitness memory witness) {
    return abi.decode((_encoded), (ChainidWitness));
  }

  struct SelfBalanceWitness { // 0x47
    uint256 opcode;
    uint256 value;
  }

  function toSelfBalanceWitness(bytes memory _encoded) internal pure returns(SelfBalanceWitness memory witness) {
    return abi.decode((_encoded), (SelfBalanceWitness));
  }

  struct SloadWitness { // 0x54
    uint256 opcode;
    bytes32 target;
    bytes32 value;
  }

  function toSloadWitness(bytes memory _encoded) internal pure returns(SloadWitness memory witness) {
    return abi.decode((_encoded), (SloadWitness));
  }

  struct SstoreWitness { // 0x55
    uint256 opcode;
    bytes32 stateRoot;
    bytes32 target;
    bytes32 value;
    uint256 gasRefund;
  }

  function toSstoreWitness(bytes memory _encoded) internal pure returns(SstoreWitness memory witness) {
    return abi.decode((_encoded), (SstoreWitness));
  }

  struct CallWitness { // 0xf1
    uint256 opcode;
    bytes32 stateRootLeave;
    uint256 gasGiven;
    uint256 gasUsed;
    uint256 gasRefund;
    address target;
    uint256 value;
    bytes32 calldataHash;
    bool success;
    bytes returndata;
  }

  function toCallWitness(bytes memory _encoded) internal pure returns(CallWitness memory witness) {
    return abi.decode((_encoded), (CallWitness));
  }

  struct CallCodeWitness { // 0xf2
    uint256 opcode;
    bytes32 stateRootLeave;
    uint256 gasGiven;
    uint256 gasUsed;
    uint256 gasRefund;
    address target;
    uint256 value;
    bytes32 calldataHash;
    bool success;
    bytes returndata;
  }

  function toCallCodeWitness(bytes memory _encoded) internal pure returns(CallCodeWitness memory witness) {
    return abi.decode((_encoded), (CallCodeWitness));
  }

  struct DelegateCallWitness { // 0xf4
    uint256 opcode;
    bytes32 stateRootLeave;
    uint256 gasGiven;
    uint256 gasUsed;
    uint256 gasRefund;
    address target;
    bytes32 calldataHash;
    bool success;
    bytes returndata;
  }

  function toDelegateCallWitness(bytes memory _encoded) internal pure returns(DelegateCallWitness memory witness) {
    return abi.decode((_encoded), (DelegateCallWitness));
  }

  struct StaticCallWitness { // 0xfa
    uint256 opcode;
    uint256 gasGiven;
    uint256 gasUsed;
    address target;
    bytes32 calldataHash;
    bool success;
    bytes returndata;
  }

  function toStaticCallWitness(bytes memory _encoded) internal pure returns(StaticCallWitness memory witness) {
    return abi.decode((_encoded), (StaticCallWitness));
  }

  struct AccessRecordMeta {
    uint256 opcode;
    bytes32 ptr;
  }

  /* function toMetaRecord(bytes memory record) internal pure returns (uint256 opcode, bytes32 ptr) {
    assembly {
      opcode := mload(add(record, 0x20))
    }
    if (opcode == 0x31) {
      BalanceWitness memory witness = abi.decode((record), (BalanceWitness));
      assembly { ptr := witness }
    } else if (opcode == 0x3b) {
      ExtCodeSizeWitness memory witness = abi.decode((record), (ExtCodeSizeWitness));
      assembly { ptr := witness }
    } else if (opcode == 0x3c) {
      ExtCodeCopyWitness memory witness = abi.decode((record), (ExtCodeCopyWitness));
      assembly { ptr := witness }
    } else if (opcode == 0x3f) {
      ExtCodeHashWitness memory witness = abi.decode((record), (ExtCodeHashWitness));
      assembly { ptr := witness }
    } else if (opcode == 0x40) {
      BlockHashWitness memory witness = abi.decode((record), (BlockHashWitness));
      assembly { ptr := witness }
    } else if (opcode == 0x41) {
      CoinbaseWitness memory witness = abi.decode((record), (CoinbaseWitness));
      assembly { ptr := witness }
    } else if (opcode == 0x42) {
      TimestampWitness memory witness = abi.decode((record), (TimestampWitness));
      assembly { ptr := witness }
    } else if (opcode == 0x43) {
      NumberWitness memory witness = abi.decode((record), (NumberWitness));
      assembly { ptr := witness }
    } else if (opcode == 0x44) {
      DifficultyWitness memory witness = abi.decode((record), (DifficultyWitness));
      assembly { ptr := witness }
    } else if (opcode == 0x45) {
      GaslimitWitness memory witness = abi.decode((record), (GaslimitWitness));
      assembly { ptr := witness }
    } else if (opcode == 0x46) {
      ChainidWitness memory witness = abi.decode((record), (ChainidWitness));
      assembly { ptr := witness }
    } else if (opcode == 0x47) {
      SelfBalanceWitness memory witness = abi.decode((record), (SelfBalanceWitness));
      assembly { ptr := witness }
    } else if (opcode == 0x54) {
      SloadWitness memory witness = abi.decode((record), (SloadWitness));
      assembly { ptr := witness }
    } else if (opcode == 0x55) {
      SstoreWitness memory witness = abi.decode((record), (SstoreWitness));
      assembly { ptr := witness }
    } else if (opcode == 0xf1) {
      CallWitness memory witness = abi.decode((record), (CallWitness));
      assembly { ptr := witness }
    } else if (opcode == 0xf2) {
      CallCodeWitness memory witness = abi.decode((record), (CallCodeWitness));
      assembly { ptr := witness }
    } else if (opcode == 0xf4) {
      DelegateCallWitness memory witness = abi.decode((record), (DelegateCallWitness));
      assembly { ptr := witness }
    } else if (opcode == 0xfa) {
      StaticCallWitness memory witness = abi.decode((record), (StaticCallWitness));
      assembly { ptr := witness }
    }
  } */
}