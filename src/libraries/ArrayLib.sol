// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

/// @title  ArrayLib
library ArrayLib {
    function countNonZeroValues(uint16[8] memory arr) internal pure returns (uint8 count) {
        for (uint256 i; i < arr.length; i++) {
            if (arr[i] != 0) ++count;
        }
    }

    function decreaseFirstNValues(uint16[8] storage arr, uint8 numValues) internal {
        for (uint256 i; i < arr.length; i++) {
            if (numValues == 0) return;

            if (arr[i] != 0) {
                arr[i] -= 1;
                numValues--;
            }
        }

        require(numValues == 0, "ArrayLib/invalid-values");
    }

    function isEmpty(uint16[8] memory arr) internal pure returns (bool) {
        for (uint256 i; i < arr.length; i++) {
            if (arr[i] != 0) return false;
        }
        return true;
    }
}
