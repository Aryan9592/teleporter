// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../TeleporterProxy.sol";
import "./TeleporterMessengerTest.t.sol";

// Parent contract for TeleporterMessenger tests. Deploys a TeleporterMessenger
// instance in the test setup, and provides helper methods for sending and
// receiving empty mock messages.
contract TeleportProxyTests is TeleporterMessengerTest {
    event Upgraded(address indexed implementation);

    TeleporterProxy private _teleporterProxy;

    // Address that the out-of-band warp message sets as the "source" address.
    // The address is obviously not owned by any EOA or smart contract account, so it
    // can not possibly be the source address of any other warp message emitted by the VM.
    bytes32 constant VALIDATORS_SOURCE_ADDRESS =
        0x0000000000000000000000000000000000000000000000000000000000000000;

    function setUp() public virtual override {
        TeleporterMessengerTest.setUp();
        _teleporterProxy = new TeleporterProxy(address(teleporterMessenger));
    }

    function testInvalidTeleporterAddress() public {
        // Try to deploy a TeleporterProxy with a zero address. Expect revert.
        vm.expectRevert("ERC1967: new implementation is not a contract");
        _teleporterProxy = new TeleporterProxy(address(0));
    }

    function testUpdateProtocolAddressSuccess() public {
        uint256 nonce = _teleporterProxy.getNonce();
        TeleporterMessenger newTeleporter = new TeleporterMessenger();
        WarpMessage memory warpMessage = _createWarpUpdateMessage(
            nonce + 1,
            address(newTeleporter)
        );

        // Mock the call to the warp precompile to get the message.
        setUpSuccessGetVerifiedWarpMessageMock(warpMessage);

        vm.expectEmit(true, false, false, false, address(_teleporterProxy));
        emit Upgraded(address(newTeleporter));
        _teleporterProxy.updateProtocolAddress();

        assertEq(_teleporterProxy.getNonce(), nonce + 1);
        assertEq(_teleporterProxy.getProtocolAddress(), address(newTeleporter));
    }

    function testSendMessageNoFee() public {
        // Arrange
        TeleporterMessage memory expectedMessage = createMockTeleporterMessage(
            1,
            hex"deadbeef"
        );
        TeleporterMessageInput memory messageInput = TeleporterMessageInput({
            destinationChainID: DEFAULT_DESTINATION_CHAIN_ID,
            destinationAddress: expectedMessage.destinationAddress,
            feeInfo: TeleporterFeeInfo(address(0), 0),
            requiredGasLimit: expectedMessage.requiredGasLimit,
            allowedRelayerAddresses: expectedMessage.allowedRelayerAddresses,
            message: expectedMessage.message
        });

        // We have to mock the precompile call so that the test does not revert.
        vm.mockCall(
            WARP_PRECOMPILE_ADDRESS,
            abi.encodePacked(WarpMessenger.sendWarpMessage.selector),
            new bytes(0)
        );

        // Expect the exact message to be passed to the precompile.
        vm.expectCall(
            WARP_PRECOMPILE_ADDRESS,
            abi.encodeCall(
                WarpMessenger.sendWarpMessage,
                (
                    messageInput.destinationChainID,
                    this.addressToBytes32(address(_teleporterProxy)),
                    abi.encode(expectedMessage)
                )
            )
        );

        // Expect the SendCrossChainMessage event to be emitted.
        vm.expectEmit(true, true, true, true, address(_teleporterProxy));
        emit SendCrossChainMessage(
            messageInput.destinationChainID,
            expectedMessage.messageID,
            expectedMessage
        );

        // Get message ID from teleporter messenger contract that should not change.
        uint256 teleporterMessageID = teleporterMessenger.getNextMessageID(
            DEFAULT_DESTINATION_CHAIN_ID
        );
        assertEq(teleporterMessageID, 1);
        // Act
        TeleporterMessenger _teleporterMessenger = TeleporterMessenger(
            address(_teleporterProxy)
        );
        uint256 messageID = _teleporterMessenger.sendCrossChainMessage(
            messageInput
        );

        // Verify that teleporter messaeg ID did not increment from calling proxy.
        assertEq(teleporterMessageID, 1);

        // Assert
        assertEq(messageID, 1);
        assertEq(
            _teleporterMessenger.getNextMessageID(DEFAULT_DESTINATION_CHAIN_ID),
            2
        );

        messageID = _teleporterMessenger.sendCrossChainMessage(messageInput);
        assertEq(messageID, 2);
        (bool success, bytes memory data) = address(_teleporterProxy).call(
            abi.encodeWithSelector(
                TeleporterMessenger.sendCrossChainMessage.selector,
                messageInput
            )
        );
        assertTrue(success);
        messageID = abi.decode(data, (uint256));
        assertEq(messageID, 3);
    }

    function testReceiveCrossChainMessage() public {
        // This test contract must be an allowed relayer since it is what
        // will call receiveCrossSubnetMessage.
        bytes
            memory defaultMessagePayload = hex"cafebabe11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff11223344556677889900aabbccddeeffdeadbeef";

        address[] memory allowedRelayers = new address[](2);
        allowedRelayers[0] = address(this);
        allowedRelayers[1] = DEFAULT_RELAYER_REWARD_ADDRESS;

        // Construct the test message to be received.
        TeleporterMessage memory messageToReceive = TeleporterMessage({
            messageID: 42,
            senderAddress: address(this),
            destinationAddress: DEFAULT_DESTINATION_ADDRESS,
            requiredGasLimit: DEFAULT_REQUIRED_GAS_LIMIT,
            allowedRelayerAddresses: allowedRelayers,
            receipts: new TeleporterMessageReceipt[](0),
            message: defaultMessagePayload
        });
        WarpMessage memory warpMessage = WarpMessage({
            originChainID: DEFAULT_ORIGIN_CHAIN_ID,
            originSenderAddress: this.addressToBytes32(
                address(_teleporterProxy)
            ),
            destinationChainID: MOCK_BLOCK_CHAIN_ID,
            destinationAddress: this.addressToBytes32(
                address(_teleporterProxy)
            ),
            payload: abi.encode(messageToReceive)
        });

        // Mock the call to the warp precompile to get the message.
        setUpSuccessGetVerifiedWarpMessageMock(warpMessage);

        // Receive the message.
        TeleporterMessenger _teleporterMessenger = TeleporterMessenger(
            address(_teleporterProxy)
        );
        _teleporterMessenger.receiveCrossChainMessage(
            DEFAULT_RELAYER_REWARD_ADDRESS
        );
    }

    function testInvalidWarpOriginChainId() public {
        WarpMessage memory warpMessage = _createWarpUpdateMessage(
            _teleporterProxy.getNonce() + 1,
            address(teleporterMessenger)
        );

        // Change the origin chain ID to something invalid.
        warpMessage.originChainID = DEFAULT_DESTINATION_CHAIN_ID;

        // Mock the call to the warp precompile to get the message.
        setUpSuccessGetVerifiedWarpMessageMock(warpMessage);

        vm.expectRevert("Invalid origin chain ID.");
        _teleporterProxy.updateProtocolAddress();
    }

    function testInvalidWarpDestinationChainId() public {
        WarpMessage memory warpMessage = _createWarpUpdateMessage(
            _teleporterProxy.getNonce() + 1,
            address(teleporterMessenger)
        );

        // Change the origin chain ID to something invalid.
        warpMessage.destinationChainID = DEFAULT_DESTINATION_CHAIN_ID;

        // Mock the call to the warp precompile to get the message.
        setUpSuccessGetVerifiedWarpMessageMock(warpMessage);

        vm.expectRevert("Invalid destination chain ID.");
        _teleporterProxy.updateProtocolAddress();
    }

    function testInvalidOriginSenderAddress() public {
        WarpMessage memory warpMessage = _createWarpUpdateMessage(
            _teleporterProxy.getNonce() + 1,
            address(teleporterMessenger)
        );

        // Change the origin chain ID to something invalid.
        warpMessage.originSenderAddress = this.addressToBytes32(
            DEFAULT_DESTINATION_ADDRESS
        );

        // Mock the call to the warp precompile to get the message.
        setUpSuccessGetVerifiedWarpMessageMock(warpMessage);

        vm.expectRevert("Invalid origin sender address.");
        _teleporterProxy.updateProtocolAddress();
    }

    function testInvalidDestinationAddress() public {
        WarpMessage memory warpMessage = _createWarpUpdateMessage(
            _teleporterProxy.getNonce() + 1,
            address(teleporterMessenger)
        );

        // Change the origin chain ID to something invalid.
        warpMessage.destinationAddress = this.addressToBytes32(
            address(teleporterMessenger)
        );

        // Mock the call to the warp precompile to get the message.
        setUpSuccessGetVerifiedWarpMessageMock(warpMessage);

        vm.expectRevert("Invalid destination address.");
        _teleporterProxy.updateProtocolAddress();
    }

    function testInvalidNonce() public {
        WarpMessage memory warpMessage = _createWarpUpdateMessage(
            _teleporterProxy.getNonce(),
            address(teleporterMessenger)
        );

        // Mock the call to the warp precompile to get the message.
        setUpSuccessGetVerifiedWarpMessageMock(warpMessage);

        vm.expectRevert("Invalid nonce.");
        _teleporterProxy.updateProtocolAddress();
    }

    function _createWarpUpdateMessage(
        uint256 nonce,
        address newProtocolAddress
    ) private view returns (WarpMessage memory) {
        return
            WarpMessage({
                originChainID: MOCK_BLOCK_CHAIN_ID,
                originSenderAddress: VALIDATORS_SOURCE_ADDRESS,
                destinationChainID: MOCK_BLOCK_CHAIN_ID,
                destinationAddress: this.addressToBytes32(
                    address(_teleporterProxy)
                ),
                payload: abi.encode(nonce, newProtocolAddress)
            });
    }
}
