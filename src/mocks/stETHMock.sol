// // SPDX-License-Identifier: GPL-3.0

// pragma solidity 0.8.20;

// import "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
// import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
// /**
//  * @title Interest-bearing ERC20-like token for Zybra protocol.
//  *
//  * This contract is abstract. To make the contract deployable override the
//  * `_getTotalMintedEUSD` function. `Zybra.sol` contract inherits EUSD and defines
//  * the `_getTotalMintedEUSD` function.
//  *
//  * EUSD balances are dynamic and represent the holder's share in the total amount
//  * of Ether controlled by the protocol. Account shares aren't normalized, so the
//  * contract also stores the sum of all shares to calculate each account's token balance
//  * which equals to:
//  *
//  *   shares[account] * _getTotalMintedEUSD() / _getTotalShares()
//  *
//  * For example, assume that we have:
//  *
//  *   _getTotalMintedEUSD() -> 1000 EUSD
//  *   sharesOf(user1) -> 100
//  *   sharesOf(user2) -> 400
//  *
//  * Therefore:
//  *
//  *   balanceOf(user1) -> 2 tokens which corresponds 200 EUSD
//  *   balanceOf(user2) -> 8 tokens which corresponds 800 EUSD
//  *
//  * Since balances of all token holders change when the amount of total supplied EUSD
//  * changes, this token cannot fully implement ERC20 standard: it only emits `Transfer`
//  * events upon explicit transfer between holders. In contrast, when total amount of
//  * pooled Ether increases, no `Transfer` events are generated: doing so would require
//  * emitting an event for each token holder and thus running an unbounded loop.
//  */
// contract stETHMock is IERC20 {
//     using Math for uint256;
//     uint256 private totalShares;

//     uint256 totalEther;
//     uint256 updateTime;

//     /**
//      * @dev EUSD balances are dynamic and are calculated based on the accounts' shares
//      * and the total supply by the protocol. Account shares aren't
//      * normalized, so the contract also stores the sum of all shares to calculate
//      * each account's token balance which equals to:
//      *
//      *   shares[account] * _getTotalMintedEUSD() / _getTotalShares()
//      */
//     mapping(address => uint256) private shares;

//     /**
//      * @dev Allowances are nominated in tokens, not token shares.
//      */
//     mapping(address => mapping(address => uint256)) private allowances;

//     /**
//      * @notice An executed shares transfer from `sender` to `recipient`.
//      *
//      * @dev emitted in pair with an ERC20-defined `Transfer` event.
//      */
//     event TransferShares(
//         address indexed from,
//         address indexed to,
//         uint256 sharesValue
//     );

//     /**
//      * @notice An executed `burnShares` request
//      *
//      * @dev Reports simultaneously burnt shares amount
//      * and corresponding EUSD amount.
//      * The EUSD amount is calculated twice: before and after the burning incurred rebase.
//      *
//      * @param account holder of the burnt shares
//      * @param preRebaseTokenAmount amount of EUSD the burnt shares corresponded to before the burn
//      * @param postRebaseTokenAmount amount of EUSD the burnt shares corresponded to after the burn
//      * @param sharesAmount amount of burnt shares
//      */
//     event SharesBurnt(
//         address indexed account,
//         uint256 preRebaseTokenAmount,
//         uint256 postRebaseTokenAmount,
//         uint256 sharesAmount
//     );

//     constructor() {
//         _mintShares(msg.sender, 10000 * 1e18);
//         totalEther = 10000 * 1e18;
//         updateTime = block.timestamp;
//     }

//     function submit(address user) external payable returns(uint256) {
//         uint256 sharesAmount = getSharesByPooledEth(msg.value);

//         _mintShares(msg.sender, sharesAmount);
//         totalEther = _getTotalMintedEUSD() + msg.value;
//         updateTime = block.timestamp;
//         return sharesAmount;
//     }

//     function claimTestStETH() external {
//         _mintShares(msg.sender, 100 * 1e18);
//     }

//     /**
//      * @dev mock stETH are expanding at a ratio of 1% a day
//      */
//     function _getTotalMintedEUSD() internal view returns (uint256) {
//         return totalEther + totalEther * (block.timestamp - updateTime) / 365 / 20 days ;
//     }

//     /**
//      * @return the name of the token.
//      */
//     function name() public pure virtual returns (string memory) {
//         return "stETH";
//     }

//     /**
//      * @return the symbol of the token, usually a shorter version of the
//      * name.
//      */
//     function symbol() public pure virtual returns (string memory) {
//         return "stETH";
//     }

//     /**
//      * @return the number of decimals for getting user representation of a token amount.
//      */
//     function decimals() public pure returns (uint8) {
//         return 18;
//     }

//     /**
//      * @return the amount of EUSD in existence.
//      *
//      * @dev Always equals to `_getTotalMintedEUSD()` since token amount
//      * is pegged to the total amount of EUSD controlled by the protocol.
//      */
//     function totalSupply() public view returns (uint256) {
//         return _getTotalMintedEUSD();
//     }

//     /**
//      * @return the amount of tokens owned by the `_account`.
//      *
//      * @dev Balances are dynamic and equal the `_account`'s share in the amount of the
//      * total Ether controlled by the protocol. See `sharesOf`.
//      */
//     function balanceOf(address _account) public view returns (uint256) {
//         return getPooledEthByShares(_sharesOf(_account));
//     }

//     /**
//      * @notice Moves `_amount` tokens from the caller's account to the `_recipient` account.
//      *
//      * @return a boolean value indicating whether the operation succeeded.
//      * Emits a `Transfer` event.
//      * Emits a `TransferShares` event.
//      *
//      * Requirements:
//      *
//      * - `_recipient` cannot be the zero address.
//      * - the caller must have a balance of at least `_amount`.
//      * - the contract must not be paused.
//      *
//      * @dev The `_amount` argument is the amount of tokens, not shares.
//      */
//     function transfer(
//         address _recipient,
//         uint256 _amount
//     ) public returns (bool) {
//         _transfer(msg.sender, _recipient, _amount);
//         return true;
//     }

//     /**
//      * @return the remaining number of tokens that `_spender` is allowed to spend
//      * on behalf of `_owner` through `transferFrom`. This is zero by default.
//      *
//      * @dev This value changes when `approve` or `transferFrom` is called.
//      */
//     function allowance(
//         address _owner,
//         address _spender
//     ) public view returns (uint256) {
//         return allowances[_owner][_spender];
//     }

//     /**
//      * @notice Sets `_amount` as the allowance of `_spender` over the caller's tokens.
//      *
//      * @return a boolean value indicating whether the operation succeeded.
//      * Emits an `Approval` event.
//      *
//      * Requirements:
//      *
//      * - `_spender` cannot be the zero address.
//      * - the contract must not be paused.
//      *
//      * @dev The `_amount` argument is the amount of tokens, not shares.
//      */
//     function approve(address _spender, uint256 _amount) public returns (bool) {
//         _approve(msg.sender, _spender, _amount);
//         return true;
//     }

//     /**
//      * @notice Moves `_amount` tokens from `_sender` to `_recipient` using the
//      * allowance mechanism. `_amount` is then deducted from the caller's
//      * allowance.
//      *
//      * @return a boolean value indicating whether the operation succeeded.
//      *
//      * Emits a `Transfer` event.
//      * Emits a `TransferShares` event.
//      * Emits an `Approval` event indicating the updated allowance.
//      *
//      * Requirements:
//      *
//      * - `_sender` and `_recipient` cannot be the zero addresses.
//      * - `_sender` must have a balance of at least `_amount`.
//      * - the caller must have allowance for `_sender`'s tokens of at least `_amount`.
//      * - the contract must not be paused.
//      *
//      * @dev The `_amount` argument is the amount of tokens, not shares.
//      */
//     function transferFrom(
//         address _sender,
//         address _recipient,
//         uint256 _amount
//     ) public returns (bool) {
//         uint256 currentAllowance = allowances[_sender][msg.sender];
//         require(
//             currentAllowance >= _amount,
//             "TRANSFER_AMOUNT_EXCEEDS_ALLOWANCE"
//         );

//         _transfer(_sender, _recipient, _amount);
//         _approve(_sender, msg.sender, currentAllowance.sub(_amount));
//         return true;
//     }

//     /**
//      * @notice Atomically increases the allowance granted to `_spender` by the caller by `_addedValue`.
//      *
//      * This is an alternative to `approve` that can be used as a mitigation for
//      * problems described in:
//      * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol#L42
//      * Emits an `Approval` event indicating the updated allowance.
//      *
//      * Requirements:
//      *
//      * - `_spender` cannot be the the zero address.
//      * - the contract must not be paused.
//      */
//     function increaseAllowance(
//         address _spender,
//         uint256 _addedValue
//     ) public returns (bool) {
//         _approve(
//             msg.sender,
//             _spender,
//             allowances[msg.sender][_spender].add(_addedValue)
//         );
//         return true;
//     }

//     /**
//      * @notice Atomically decreases the allowance granted to `_spender` by the caller by `_subtractedValue`.
//      *
//      * This is an alternative to `approve` that can be used as a mitigation for
//      * problems described in:
//      * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol#L42
//      * Emits an `Approval` event indicating the updated allowance.
//      *
//      * Requirements:
//      *
//      * - `_spender` cannot be the zero address.
//      * - `_spender` must have allowance for the caller of at least `_subtractedValue`.
//      * - the contract must not be paused.
//      */
//     function decreaseAllowance(
//         address _spender,
//         uint256 _subtractedValue
//     ) public returns (bool) {
//         uint256 currentAllowance = allowances[msg.sender][_spender];
//         require(
//             currentAllowance >= _subtractedValue,
//             "DECREASED_ALLOWANCE_BELOW_ZERO"
//         );
//         _approve(msg.sender, _spender, currentAllowance.sub(_subtractedValue));
//         return true;
//     }

//     /**
//      * @return the total amount of shares in existence.
//      *
//      * @dev The sum of all accounts' shares can be an arbitrary number, therefore
//      * it is necessary to store it in order to calculate each account's relative share.
//      */
//     function getTotalShares() public view returns (uint256) {
//         return _getTotalShares();
//     }

//     /**
//      * @return the amount of shares owned by `_account`.
//      */
//     function sharesOf(address _account) public view returns (uint256) {
//         return _sharesOf(_account);
//     }

//     /**
//      * @return the amount of shares that corresponds to `_EUSDAmount` protocol-supplied EUSD.
//      */
//     function getSharesByPooledEth(
//         uint256 _EUSDAmount
//     ) public view returns (uint256) {
//         uint256 totalMintedEUSD = _getTotalMintedEUSD();
//         if (totalMintedEUSD == 0) {
//             return 0;
//         } else {
//             return _EUSDAmount.mul(_getTotalShares()).div(totalMintedEUSD);
//         }
//     }

//     /**
//      * @return the amount of EUSD that corresponds to `_sharesAmount` token shares.
//      */
//     function getPooledEthByShares(
//         uint256 _sharesAmount
//     ) public view returns (uint256) {
//         uint256 totalSharesAmount = _getTotalShares();
//         if (totalShares == 0) {
//             return 0;
//         } else {
//             return
//                 _sharesAmount.mul(_getTotalMintedEUSD()).div(totalSharesAmount);
//         }
//     }

//     /**
//      * @notice Moves `_sharesAmount` token shares from the caller's account to the `_recipient` account.
//      *
//      * @return amount of transferred tokens.
//      * Emits a `TransferShares` event.
//      * Emits a `Transfer` event.
//      *
//      * Requirements:
//      *
//      * - `_recipient` cannot be the zero address.
//      * - the caller must have at least `_sharesAmount` shares.
//      * - the contract must not be paused.
//      *
//      * @dev The `_sharesAmount` argument is the amount of shares, not tokens.
//      */
//     function transferShares(
//         address _recipient,
//         uint256 _sharesAmount
//     ) public returns (uint256) {
//         _transferShares(msg.sender, _recipient, _sharesAmount);
//         emit TransferShares(msg.sender, _recipient, _sharesAmount);
//         uint256 tokensAmount = getPooledEthByShares(_sharesAmount);
//         emit Transfer(msg.sender, _recipient, tokensAmount);
//         return tokensAmount;
//     }

//     /**
//      * @notice Moves `_amount` tokens from `_sender` to `_recipient`.
//      * Emits a `Transfer` event.
//      * Emits a `TransferShares` event.
//      */
//     function _transfer(
//         address _sender,
//         address _recipient,
//         uint256 _amount
//     ) internal {
//         uint256 _sharesToTransfer = getSharesByPooledEth(_amount);
//         _transferShares(_sender, _recipient, _sharesToTransfer);
//         emit Transfer(_sender, _recipient, _amount);
//         emit TransferShares(_sender, _recipient, _sharesToTransfer);
//     }

//     /**
//      * @notice Sets `_amount` as the allowance of `_spender` over the `_owner` s tokens.
//      *
//      * Emits an `Approval` event.
//      *
//      * Requirements:
//      *
//      * - `_owner` cannot be the zero address.
//      * - `_spender` cannot be the zero address.
//      * - the contract must not be paused.
//      */
//     function _approve(
//         address _owner,
//         address _spender,
//         uint256 _amount
//     ) internal {
//         require(_owner != address(0), "APPROVE_FROM_ZERO_ADDRESS");
//         require(_spender != address(0), "APPROVE_TO_ZERO_ADDRESS");

//         allowances[_owner][_spender] = _amount;
//         emit Approval(_owner, _spender, _amount);
//     }

//     /**
//      * @return the total amount of shares in existence.
//      */
//     function _getTotalShares() internal view returns (uint256) {
//         return totalShares;
//     }

//     /**
//      * @return the amount of shares owned by `_account`.
//      */
//     function _sharesOf(address _account) internal view returns (uint256) {
//         return shares[_account];
//     }

//     /**
//      * @notice Moves `_sharesAmount` shares from `_sender` to `_recipient`.
//      *
//      * Requirements:
//      *
//      * - `_sender` cannot be the zero address.
//      * - `_recipient` cannot be the zero address.
//      * - `_sender` must hold at least `_sharesAmount` shares.
//      * - the contract must not be paused.
//      */
//     function _transferShares(
//         address _sender,
//         address _recipient,
//         uint256 _sharesAmount
//     ) internal {
//         require(_sender != address(0), "TRANSFER_FROM_THE_ZERO_ADDRESS");
//         require(_recipient != address(0), "TRANSFER_TO_THE_ZERO_ADDRESS");

//         uint256 currentSenderShares = shares[_sender];
//         require(
//             _sharesAmount <= currentSenderShares,
//             "TRANSFER_AMOUNT_EXCEEDS_BALANCE"
//         );

//         shares[_sender] = currentSenderShares.sub(_sharesAmount);
//         shares[_recipient] = shares[_recipient].add(_sharesAmount);
//     }

//     /**
//      * @notice Creates `_sharesAmount` shares and assigns them to `_recipient`, increasing the total amount of shares.
//      * @dev This doesn't increase the token total supply.
//      *
//      * Requirements:
//      *
//      * - `_recipient` cannot be the zero address.
//      * - the contract must not be paused.
//      */
//     function _mintShares(
//         address _recipient,
//         uint256 _sharesAmount
//     ) internal returns (uint256 newTotalShares) {
//         require(_recipient != address(0), "MINT_TO_THE_ZERO_ADDRESS");

//         newTotalShares = _getTotalShares().add(_sharesAmount);
//         totalShares = newTotalShares;

//         shares[_recipient] = shares[_recipient].add(_sharesAmount);

//         // Notice: we're not emitting a Transfer event from the zero address here since shares mint
//         // works by taking the amount of tokens corresponding to the minted shares from all other
//         // token holders, proportionally to their share. The total supply of the token doesn't change
//         // as the result. This is equivalent to performing a send from each other token holder's
//         // address to `address`, but we cannot reflect this as it would require sending an unbounded
//         // number of events.
//     }

//     /**
//      * @notice Destroys `_sharesAmount` shares from `_account`'s holdings, decreasing the total amount of shares.
//      * @dev This doesn't decrease the token total supply.
//      *
//      * Requirements:
//      *
//      * - `_account` cannot be the zero address.
//      * - `_account` must hold at least `_sharesAmount` shares.
//      * - the contract must not be paused.
//      */
//     function _burnShares(
//         address _account,
//         uint256 _sharesAmount
//     ) internal returns (uint256 newTotalShares) {
//         require(_account != address(0), "BURN_FROM_THE_ZERO_ADDRESS");

//         uint256 accountShares = shares[_account];
//         require(_sharesAmount <= accountShares, "BURN_AMOUNT_EXCEEDS_BALANCE");

//         uint256 preRebaseTokenAmount = getPooledEthByShares(_sharesAmount);

//         newTotalShares = _getTotalShares().sub(_sharesAmount);
//         totalShares = newTotalShares;

//         shares[_account] = accountShares.sub(_sharesAmount);

//         uint256 postRebaseTokenAmount = getPooledEthByShares(_sharesAmount);

//         emit SharesBurnt(
//             _account,
//             preRebaseTokenAmount,
//             postRebaseTokenAmount,
//             _sharesAmount
//         );

//         // Notice: we're not emitting a Transfer event to the zero address here since shares burn
//         // works by redistributing the amount of tokens corresponding to the burned shares between
//         // all other token holders. The total supply of the token doesn't change as the result.
//         // This is equivalent to performing a send from `address` to each other token holder address,
//         // but we cannot reflect this as it would require sending an unbounded number of events.

//         // We're emitting `SharesBurnt` event to provide an explicit rebase log record nonetheless.
//     }
// }