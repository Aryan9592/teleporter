// (c) 2022-2023, Ava Labs, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "../IWarpProtocolProxy.sol";
import "./ITeleporterMessenger.sol";
import "@subnet-evm-contracts/IWarpMessenger.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract TeleporterProxy is ERC1967Proxy, IWarpProtocolProxy {
    address public constant WARP_MESSENGER_PRECOMPILE_ADDRESS =
        0x0200000000000000000000000000000000000005;
    WarpMessenger public constant WARP_MESSENGER =
        WarpMessenger(WARP_MESSENGER_PRECOMPILE_ADDRESS);

    // The blockchain ID of the chain the contract is deployed on. Determined by warp messenger precompile.
    bytes32 public immutable chainID;

    // Address that the out-of-band warp message sets as the "source" address.
    // The address is obviously not owned by any EOA or smart contract account, so it
    // can not possibly be the source address of any other warp message emitted by the VM.
    bytes32 public constant VALIDATORS_SOURCE_ADDRESS =
        0x0000000000000000000000000000000000000000000000000000000000000000;

    uint256 private _currentNonce;

    constructor(
        address _teleporterAddress
    ) ERC1967Proxy(_teleporterAddress, new bytes(0)) {
        require(_teleporterAddress != address(0), "Invalid protocol address.");
        chainID = WARP_MESSENGER.getBlockchainID();
        _currentNonce = 0;
    }

    function updateProtocolAddress() external {
        (WarpMessage memory warpMessage, bool exists) = WARP_MESSENGER
            .getVerifiedWarpMessage();
        require(exists, "No valid warp message.");

        require(
            warpMessage.originChainID == chainID,
            "Invalid origin chain ID."
        );
        require(
            warpMessage.destinationChainID == chainID,
            "Invalid destination chain ID."
        );

        require(
            warpMessage.originSenderAddress == VALIDATORS_SOURCE_ADDRESS,
            "Invalid origin sender address."
        );
        require(
            warpMessage.destinationAddress ==
                bytes32(uint256(uint160(address(this)))),
            "Invalid destination address."
        );

        (uint256 _nonce, address _newProtocolAddress) = abi.decode(
            warpMessage.payload,
            (uint256, address)
        );

        require(_nonce == _currentNonce + 1, "Invalid nonce.");
        require(_newProtocolAddress != address(0), "Invalid protocol address.");

        _upgradeTo(_newProtocolAddress);
        _currentNonce = _nonce;
    }

    function getProtocolAddress() external view returns (address) {
        return ERC1967Proxy._implementation();
    }

    function getNonce() external view returns (uint256) {
        return _currentNonce;
    }
}
