// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import { OwnableUpgradeable } from "./exports/ExternalExports.sol";
import { AssetHelper } from "./helpers/AssetHelper.sol";
import { DotcV2 } from "./DotcV2.sol";
import { DotcEscrowV2 } from "./DotcEscrowV2.sol";
import { OnlyDotc, ZeroAddressPassed, IncorrectPercentage } from "./structures/DotcStructuresV2.sol";

/// @title Errors related to management in the Dotc contract.
/// @notice Provides error messages for various failure conditions related to dotc management handling.

/**
 * @notice Thrown when pasted `feeAmount` > 10**27.
 */
error IncorrectFeeAmount(uint256 feeAmount);

/**
 * @title DotcManagerV2 (as part of the "SwarmX.eth Protocol")
 * @notice This contract manages DOTC and escrow addresses, fee settings, and other configurations for the SwarmX.eth Protocol.
 * @dev This contract is upgradable and manages key configurations for the SwarmX.eth Protocol.
 * ////////////////DISCLAIMER////////////////DISCLAIMER////////////////DISCLAIMER////////////////
 * Please read the Disclaimer featured on the SwarmX.eth website ("Terms") carefully before accessing,
 * interacting with, or using the SwarmX.eth Protocol software, consisting of the SwarmX.eth Protocol
 * technology stack (in particular its smart contracts) as well as any other SwarmX.eth technology such
 * as e.g., the launch kit for frontend operators (together the "SwarmX.eth Protocol Software").
 * By using any part of the SwarmX.eth Protocol you agree (1) to the Terms and acknowledge that you are
 * aware of the existing risk and knowingly accept it, (2) that you have read, understood and accept the
 * legal information and terms of service and privacy note presented in the Terms, and (3) that you are
 * neither a US person nor a person subject to international sanctions (in particular as imposed by the
 * European Union, Switzerland, the United Nations, as well as the USA). If you do not meet these
 * requirements, please refrain from using the SwarmX.eth Protocol.
 * ////////////////DISCLAIMER////////////////DISCLAIMER////////////////DISCLAIMER////////////////
 * @author Swarm
 */
contract DotcManagerV2 is OwnableUpgradeable {
    /**
     * @dev Emitted when the DOTC address is changed.
     * @param by Address of the user who changed the DOTC address.
     * @param dotc New DOTC's address.
     */
    event DotcAddressSet(address indexed by, DotcV2 dotc);

    /**
     * @dev Emitted when the escrow address is changed.
     * @param by Address of the user who changed the escrow address.
     * @param escrow New escrow's address.
     */
    event EscrowAddressSet(address indexed by, DotcEscrowV2 escrow);

    /**
     * @dev Emitted when the fees receiver is changed.
     * @param by Address of the user who performed the update.
     * @param feeReceiver New fees receiver's address.
     */
    event FeesReceiverSet(address indexed by, address feeReceiver);

    /**
     * @dev Emitted when the fees amount is changed.
     * @param by Address of the user who performed the update.
     * @param feeAmount New fees amount.
     */
    event FeesAmountSet(address indexed by, uint256 feeAmount);

    /**
     * @dev Emitted when the revenue share percentage is changed.
     * @param by Address of the user who performed the update.
     * @param revShareAmount New revenue share percentage.
     */
    event RevShareSet(address indexed by, uint256 revShareAmount);

    /**
     * @dev Address of the DOTC contract.
     */
    DotcV2 public dotc;

    /**
     * @dev Address of the escrow contract.
     */
    DotcEscrowV2 public escrow;

    /**
     * @dev Address to receive fees.
     */
    address public feeReceiver;

    /**
     * @dev Fee amount.
     */
    uint256 public feeAmount;

    /**
     * @dev Revenue share percentage.
     */
    uint256 public revSharePercentage;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the DotcManager contract with a fee receiver address.
     * @param _newFeeReceiver The address of the fee receiver.
     */
    function initialize(address _newFeeReceiver) public initializer {
        __Ownable_init(msg.sender);

        _changeFees(_newFeeReceiver, 25 * (10 ** 23), 8000);
    }

    /**
     * @notice Changes the DOTC contract address.
     * @param _dotc The new DOTC contract's address.
     * @dev Ensures that the new address is not zero.
     */
    function changeDotc(DotcV2 _dotc) external onlyOwner {
        if (address(_dotc) == address(0)) {
            revert ZeroAddressPassed();
        }

        dotc = _dotc;
        emit DotcAddressSet(msg.sender, _dotc);
    }

    /**
     * @notice Changes the escrow contract address.
     * @param _escrow The new escrow contract's address.
     * @dev Ensures that the new address is not zero.
     */
    function changeEscrow(DotcEscrowV2 _escrow) external onlyOwner {
        if (address(_escrow) == address(0)) {
            revert ZeroAddressPassed();
        }

        escrow = _escrow;
        emit EscrowAddressSet(msg.sender, _escrow);
    }

    /**
     * @notice Changes the DOTC address in the escrow contract.
     * @dev Ensures that only the current owner can perform this operation.
     */
    function changeDotcInEscrow() external onlyOwner {
        escrow.changeDotc(dotc);
    }

    /**
     * @notice Changes the escrow address in the DOTC contract.
     * @dev Ensures that only the current owner can perform this operation.
     */
    function changeEscrowInDotc() external onlyOwner {
        dotc.changeEscrow(escrow);
    }

    /**
     * @notice Changes the fee settings for the contract.
     * @param _newFeeReceiver The new fee receiver address.
     * @param _feeAmount The new fee amount.
     * @param _revShare The new revenue share percentage.
     * @dev Requires caller to be the owner of the contract.
     */
    function changeFees(address _newFeeReceiver, uint256 _feeAmount, uint256 _revShare) external onlyOwner {
        _changeFees(_newFeeReceiver, _feeAmount, _revShare);
    }

    function _changeFees(address _newFeeReceiver, uint256 _feeAmount, uint256 _revShare) private {
        if (_revShare > AssetHelper.SCALING_FACTOR) {
            revert IncorrectPercentage(_revShare);
        }

        if (_feeAmount > AssetHelper.BPS) {
            revert IncorrectFeeAmount(_feeAmount);
        }

        feeReceiver = _newFeeReceiver;

        feeAmount = _feeAmount;

        revSharePercentage = _revShare;

        emit RevShareSet(msg.sender, _revShare);
        emit FeesAmountSet(msg.sender, _feeAmount);
        emit FeesReceiverSet(msg.sender, _newFeeReceiver);
    }
}