// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @author Swarm Markets
/// @title
/// @notice
/// @notice

interface IAssetTokenData {
    function getIssuer(address _tokenAddress) external view returns (address);

    function getGuardian(address _tokenAddress) external view returns (address);

    function setContractToSafeguard(address _tokenAddress) external returns (bool);

    function freezeContract(address _tokenAddress) external returns (bool);

    function unfreezeContract(address _tokenAddress) external returns (bool);

    function isOnSafeguard(address _tokenAddress) external view returns (bool);

    function isContractFrozen(address _tokenAddress) external view returns (bool);

    function beforeTokenTransfer(address, address) external;

    function onlyStoredToken(address _tokenAddress) external view;

    function onlyActiveContract(address _tokenAddress) external view;

    function onlyUnfrozenContract(address _tokenAddress) external view;

    function onlyIssuer(address _tokenAddress, address _functionCaller) external view;

    function onlyIssuerOrGuardian(address _tokenAddress, address _functionCaller) external view;

    function onlyIssuerOrAgent(address _tokenAddress, address _functionCaller) external view;

    function checkIfTransactionIsAllowed(
        address _caller,
        address _from,
        address _to,
        address _tokenAddress,
        bytes4 _operation,
        bytes calldata _data
    ) external view returns (bool);

    function mustBeAuthorizedHolders(
        address _tokenAddress,
        address _from,
        address _to,
        uint256 _amount
    ) external returns (bool);

    function update(address _tokenAddress) external;

    function getCurrentRate(address _tokenAddress) external view returns (uint256);

    function getInterestRate(address _tokenAddress) external view returns (uint256, bool);

    function hasRole(bytes32 role, address account) external view returns (bool);

    function isAllowedTransferOnSafeguard(address _tokenAddress, address _account) external view returns (bool);

    function registerAssetToken(address _tokenAddress, address _issuer, address _guardian) external returns (bool);

    function transferIssuer(address _tokenAddress, address _newIssuer) external;

    function setInterestRate(address _tokenAddress, uint256 _interestRate, bool _positiveInterest) external;

    function addAgent(address _tokenAddress, address _newAgent) external;

    function removeAgent(address _tokenAddress, address _agent) external;

    function addMemberToBlacklist(address _tokenAddress, address _account) external;

    function removeMemberFromBlacklist(address _tokenAddress, address _account) external;

    function allowTransferOnSafeguard(address _tokenAddress, address _account) external;

    function preventTransferOnSafeguard(address _tokenAddress, address _account) external;
}