// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

/// @title  TransientStorage
library TransientStorage {
    function tstore(bytes32 slot, address value) internal {
        assembly {
            sstore(slot, value)
        }
    }

    function tstore(bytes32 slot, uint256 value) internal {
        assembly {
            sstore(slot, value)
        }
    }

    function tloadAddress(bytes32 slot) internal view returns (address value) {
        assembly {
            value := sload(slot)
        }
    }

    function tloadUint256(bytes32 slot) internal view returns (uint256 value) {
        assembly {
            value := sload(slot)
        }
    }
}
