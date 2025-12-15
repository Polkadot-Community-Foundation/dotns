// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title Interface for the Dot Registry
/// @notice Core registry interface defining ownership and resolution for hierarchical naming
/// @dev Implements a tree structure where each node represents a domain/subdomain
interface ENS {
    /// @notice Emitted when a subnode owner is assigned
    /// @param node Parent node identifier
    /// @param label Keccak256 hash of the subnode label
    /// @param owner Address of the new owner
    event NewOwner(bytes32 indexed node, bytes32 indexed label, address owner);

    /// @notice Emitted when node ownership is transferred
    /// @param node Node identifier
    /// @param owner Address of the new owner
    event Transfer(bytes32 indexed node, address owner);

    /// @notice Emitted when a node's resolver changes
    /// @param node Node identifier
    /// @param resolver Address of the new resolver
    event NewResolver(bytes32 indexed node, address resolver);

    /// @notice Emitted when a node's TTL changes
    /// @param node Node identifier
    /// @param ttl New time-to-live in seconds
    event NewTTL(bytes32 indexed node, uint64 ttl);

    /// @notice Emitted when operator approval changes
    /// @param owner Address of the owner
    /// @param operator Address of the operator
    /// @param approved Whether the operator is approved
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /// @notice Thrown when a condition for authorisation is not met
    error NotAuthorised();

    /// @notice Sets all parameters for a node in one transaction
    /// @param node Node identifier
    /// @param newOwner Address of the new owner
    /// @param resolver Address of the resolver
    /// @param ttl Time-to-live in seconds
    function setRecord(bytes32 node, address newOwner, address resolver, uint64 ttl) external;

    /// @notice Creates or updates a subnode with all parameters
    /// @param node Parent node identifier
    /// @param label Keccak256 hash of the subnode label
    /// @param newOwner Address of the new owner
    /// @param resolver Address of the resolver
    /// @param ttl Time-to-live in seconds
    function setSubnodeRecord(
        bytes32 node,
        bytes32 label,
        address newOwner,
        address resolver,
        uint64 ttl
    )
        external;

    /// @notice Creates or updates a subnode owner
    /// @param node Parent node identifier
    /// @param label Keccak256 hash of the subnode label
    /// @param newOwner Address of the new owner
    /// @return subnode The identifier of the created subnode
    function setSubnodeOwner(
        bytes32 node,
        bytes32 label,
        address newOwner
    )
        external
        returns (bytes32 subnode);

    /// @notice Updates the resolver for a node
    /// @param node Node identifier
    /// @param resolver Address of the new resolver
    function setResolver(bytes32 node, address resolver) external;

    /// @notice Transfers ownership of a node
    /// @param node Node identifier
    /// @param newOwner Address of the new owner
    function setOwner(bytes32 node, address newOwner) external;

    /// @notice Updates the TTL for a node
    /// @param node Node identifier
    /// @param ttl New time-to-live in seconds
    function setTTL(bytes32 node, uint64 ttl) external;

    /// @notice Grants or revokes operator permissions for all caller's nodes
    /// @param operator Address to grant/revoke permissions
    /// @param approved Whether to grant or revoke
    function setApprovalForAll(address operator, bool approved) external;

    /// @notice Retrieves the owner of a node
    /// @param node Node identifier
    /// @return nodeOwner Address of the owner
    function owner(bytes32 node) external view returns (address nodeOwner);

    /// @notice Retrieves the resolver for a node
    /// @param node Node identifier
    /// @return resolverAddress Address of the resolver
    function resolver(bytes32 node) external view returns (address resolverAddress);

    /// @notice Retrieves the TTL for a node
    /// @param node Node identifier
    /// @return nodeTTL Time-to-live in seconds
    function ttl(bytes32 node) external view returns (uint64 nodeTTL);

    /// @notice Checks if a node has been registered
    /// @param node Node identifier
    /// @return exists True if the node exists
    function recordExists(bytes32 node) external view returns (bool exists);

    /// @notice Checks if an operator is approved for an owner
    /// @param recordOwner Address of the owner
    /// @param operator Address of the operator
    /// @return approved True if the operator is approved
    function isApprovedForAll(
        address recordOwner,
        address operator
    )
        external
        view
        returns (bool approved);
}
