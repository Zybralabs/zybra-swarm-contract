// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;
import {FixedPointMathLib} from "../exports/ExternalExports.sol";

library StorageLib {
    function clearOfferStorage(
        uint256 offerId,
        bytes32 depositAmountsSlot,
        bytes32 withdrawalAmountsSlot
    ) internal {
        assembly {
            // Calculate storage slots for both mappings
            mstore(0x00, offerId)
            mstore(0x20, depositAmountsSlot)
            let depositMapSlot := keccak256(0x00, 0x40)

            mstore(0x00, offerId)
            mstore(0x20, withdrawalAmountsSlot)
            let withdrawalMapSlot := keccak256(0x00, 0x40)

            // Clear storage values
            sstore(depositMapSlot, 0)
            sstore(withdrawalMapSlot, 0)
        }
    }
}




library FeeLib {
    using FixedPointMathLib for uint256;

    function calculateFee(uint256 borrowed) internal pure returns (uint256) {
        return borrowed.fullMulDiv(86_400, 365).fullMulDiv(100, 10_000);
    }

    function updateFee(
        address user,
        address asset,
        uint256 borrowed,
        mapping(address => uint256) storage _feeUpdatedAt,
        mapping(address => uint256) storage feeStored
    ) internal {
        if (block.timestamp > _feeUpdatedAt[user]) {
            feeStored[user] += calculateFee(borrowed);
            _feeUpdatedAt[user] = block.timestamp;
        }
    }
}


library DecimalLib {
    function convertDecimals(
        uint256 amount,
        uint8 fromDecimals,
        uint8 toDecimals
    ) internal pure returns (uint256) {
        if (fromDecimals == toDecimals) return amount;
        
        if (fromDecimals < toDecimals) {
            return amount * (10 ** (toDecimals - fromDecimals));
        } else {
            return amount / (10 ** (fromDecimals - toDecimals));
        }
    }
}