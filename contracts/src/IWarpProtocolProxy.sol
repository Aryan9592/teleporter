// (c) 2022-2023, Ava Labs, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.16;

interface IWarpProtocolProxy {
    event UpdateProtocolAddress(
        address indexed oldProtocolAddress,
        address indexed newProtocolAddress
    );

    function updateProtocolAddress() external;

    function getProtocolAddress() external view returns (address);
}
