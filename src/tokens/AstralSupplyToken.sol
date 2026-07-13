// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IERC20 } from "../interfaces/IERC20.sol";
import { ISupplyTokenHook } from "../interfaces/ISupplyTokenHook.sol";

/// @title AstralSupplyToken
/// @notice Non-upgradeable receipt token minted by an Astral collateral vault.
contract AstralSupplyToken is IERC20 {
    string public override name;
    string public override symbol;
    uint8 public immutable override decimals;
    address public immutable pool;
    address public immutable asset;

    uint256 public override totalSupply;

    mapping(address account => uint256 amount) public override balanceOf;
    mapping(address owner => mapping(address spender => uint256 amount)) public override allowance;

    error UnauthorizedPool(address caller);
    error InvalidRecipient();
    error InsufficientBalance(address account, uint256 balance, uint256 requested);
    error InsufficientAllowance(
        address owner, address spender, uint256 allowance, uint256 requested
    );

    constructor(
        address pool_,
        address asset_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) {
        pool = pool_;
        asset = asset_;
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
    }

    modifier onlyPool() {
        if (msg.sender != pool) revert UnauthorizedPool(msg.sender);
        _;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount, true);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount)
        external
        override
        returns (bool)
    {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < amount) revert InsufficientAllowance(from, msg.sender, allowed, amount);
            allowance[from][msg.sender] = allowed - amount;
            emit Approval(from, msg.sender, allowed - amount);
        }
        _transfer(from, to, amount, true);
        return true;
    }

    function mint(address to, uint256 amount) external onlyPool {
        if (to == address(0)) revert InvalidRecipient();
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external onlyPool {
        uint256 balance = balanceOf[from];
        if (balance < amount) revert InsufficientBalance(from, balance, amount);
        balanceOf[from] = balance - amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }

    function transferOnLiquidation(address from, address to, uint256 amount) external onlyPool {
        _transfer(from, to, amount, false);
    }

    function _transfer(address from, address to, uint256 amount, bool validate) internal {
        if (to == address(0)) revert InvalidRecipient();
        uint256 balance = balanceOf[from];
        if (balance < amount) revert InsufficientBalance(from, balance, amount);
        if (validate && from != address(0) && amount != 0) {
            ISupplyTokenHook(pool)
                .validateSupplyTokenTransfer(asset, from, to, amount, balance, totalSupply);
        }
        balanceOf[from] = balance - amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}
