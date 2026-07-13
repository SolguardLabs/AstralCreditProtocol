// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title AstralRoles
/// @notice Lightweight role manager used by protocol components.
abstract contract AstralRoles {
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant CONFIGURATOR_ROLE = keccak256("ASTRAL_CONFIGURATOR_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("ASTRAL_GUARDIAN_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("ASTRAL_TREASURY_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ASTRAL_ORACLE_ROLE");

    mapping(bytes32 role => mapping(address account => bool enabled)) private _roles;
    mapping(bytes32 role => bytes32 adminRole) private _roleAdmins;

    error UnauthorizedRole(address account, bytes32 role);
    error ZeroAddress();
    error RoleAlreadyGranted(address account, bytes32 role);
    error RoleNotGranted(address account, bytes32 role);

    event RoleAdminChanged(
        bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole
    );
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    constructor(address initialAdmin) {
        if (initialAdmin == address(0)) revert ZeroAddress();
        _roleAdmins[DEFAULT_ADMIN_ROLE] = DEFAULT_ADMIN_ROLE;
        _roleAdmins[CONFIGURATOR_ROLE] = DEFAULT_ADMIN_ROLE;
        _roleAdmins[GUARDIAN_ROLE] = DEFAULT_ADMIN_ROLE;
        _roleAdmins[TREASURY_ROLE] = DEFAULT_ADMIN_ROLE;
        _roleAdmins[ORACLE_ROLE] = DEFAULT_ADMIN_ROLE;
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(CONFIGURATOR_ROLE, initialAdmin);
        _grantRole(GUARDIAN_ROLE, initialAdmin);
    }

    modifier onlyRole(bytes32 role) {
        _checkRole(role, msg.sender);
        _;
    }

    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role][account];
    }

    function getRoleAdmin(bytes32 role) public view returns (bytes32) {
        bytes32 admin = _roleAdmins[role];
        return admin == bytes32(0) && role != DEFAULT_ADMIN_ROLE ? DEFAULT_ADMIN_ROLE : admin;
    }

    function grantRole(bytes32 role, address account) external onlyRole(getRoleAdmin(role)) {
        if (account == address(0)) revert ZeroAddress();
        if (_roles[role][account]) revert RoleAlreadyGranted(account, role);
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external onlyRole(getRoleAdmin(role)) {
        if (!_roles[role][account]) revert RoleNotGranted(account, role);
        _revokeRole(role, account);
    }

    function renounceRole(bytes32 role) external {
        if (!_roles[role][msg.sender]) revert RoleNotGranted(msg.sender, role);
        _revokeRole(role, msg.sender);
    }

    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal {
        bytes32 previous = getRoleAdmin(role);
        _roleAdmins[role] = adminRole;
        emit RoleAdminChanged(role, previous, adminRole);
    }

    function _grantRole(bytes32 role, address account) internal {
        if (account == address(0)) revert ZeroAddress();
        _roles[role][account] = true;
        emit RoleGranted(role, account, msg.sender);
    }

    function _revokeRole(bytes32 role, address account) internal {
        _roles[role][account] = false;
        emit RoleRevoked(role, account, msg.sender);
    }

    function _checkRole(bytes32 role, address account) internal view {
        if (!_roles[role][account]) revert UnauthorizedRole(account, role);
    }
}
