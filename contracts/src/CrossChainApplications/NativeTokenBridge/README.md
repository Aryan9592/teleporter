# Native-to-Native Token Bridge

A pair of smart contracts built on top of Teleporter to support using the native token of any `subnet-evm` chain as the native token for a given subnet.

## Design
The native-to-native bridge is implemented using two primary contracts.
- `NativeTokenSource`
    - Lives on the `Source chain`. Pairs with exactly one `NativeTokenDestination` contract on a different chain.
    - Locks and unlocks tokens on the Source chain corresponding to mints and burns on the destination chain.
    - `transferToDestination`: transfers all tokens payed to this function call to `recipient` on the destination chain by locking them and instructing the destination chain to mint. Optionally takes the address of an ERC20 contract `feeContractAddress` as well as an amount `feeAmount` that will be used as the relayer-incentivisation for the teleporter cross-chain call. Also allows for the caller to specify `allowedRelayerAddresses`.
    - `receiveTeleporterMessage`: unlocks tokens on the source chain when instructed to by the `NativeTokenDestination` contract.
- `NativeTokenDestination`
    - Lives on the `Destination chain`. Pairs with exactly one `NativeTokenSource` contract on a different chain.
    - Mints and burns tokens on the Destination chain corresponding to locks and unlocks on the source chain.
    - `transferToSource`: transfers all tokens payed to this function call to `recipient` on the source chain by burning the tokens and instructing the source chain to unlock. Optionally takes the address of an ERC20 contract `feeContractAddress` as well as an amount `feeAmount` that will be used as the relayer-incentivisation for the teleporter cross-chain call. Also allows for the caller to specify `allowedRelayerAddresses`.
    - `receiveTeleporterMessage`: mints tokens on the destination chain when instructed to by the `NativeTokenDestination` contract.

- `Collateralizing the bridge`
    - On initialization, the bridge will be undercollateralized by exactly the number of tokens included in genesis on the destination chain. These tokens could theoretically be sent through the bridge, with no corresponding tokens able to be unlocked on the source chain. In order to avoid this problem, the `NativeTokenDestination` contract is initialized with the value for `tokenReserve`, which should correspond to the number of tokens allocated in the genesis block for the destination chain. If this is not properly set, behaviour of this contract is undefined. The `NativeTokenDestination` contract will not mint tokens until it has received confirmation that at least `tokenReserve` tokens have been locked on the source chain. It should be up to the contract deployer to ensure that the bridge is properly collateralized. Burning/unlocking is disabled until the bridge is properly collateralized.

- `Burning tokens spent as fees`
    - As tokens are burned for transaction fees on the destination chain, we may want to relay this information to the source chain in order to burn an equivalent number of locked tokens there because these tokens will never be bridged back.
    - The address for burned transaction fees is `0x0100000000000000000000000000000000000000`. We will send tokens that are "burned" in order to unlock tokens on the source chain to a different address so that `0x0100000000000000000000000000000000000000` will only include burned transaction fees (or tokens others have decided to burn outside of this contract) so that we can report this number to the source chain to burn an equivalent numbers of locked tokens.
    - `TODO` explain implementation.

- `Setup`
    - `Teleporter` must be deployed on both chains, and the address must be passed to the constructor of both contracts.
    - `NativeTokenDestination` is meant to be deployed on a new subnet, and should be the only method for minting tokens on that subnet. The address of `NativeTokenDestination` must be included as the only entry for `adminAddresses` under `contractNativeMinterConfig` in the genesis config for the destination subnet. See `warp-genesis.json` for an example.
    - Both `NativeTokenSource` and `NativeTokenDestination` need to be deployed to addresses known beforehand. Each address must be passed to the constructor of the other contract. To do this, you will need a known EOA, and preferably use the first transaction from this address (nonce 0) to deploy the contract on each chain. It is advised to allocate tokens to the EOA in the destination subnet genesis file so that it can easily deploy the contract.
    - Both contracts need to be initialized with `teleporterMessengerAddress`, which is the only address they will accept function calls from.
    - `NativeTokenDestination` needs to be intialized with `tokenReserve`, which should equal the number of tokens allocated in the genesis file for the destination chain. If this value is not properly set, behavior of these contracts in undefined.
    - On the source chain, at least `tokenReserve` tokens need to be transfered to `NativeTokenSource` using `transferToSource` in order to properly collateralize the bridge and allow regular functionality in both directions. The first `tokenReserve` tokens will not be delivered to the recipient, but any excess will be delivered. Burning/unlocking is disabled until the bridge is fully collateralized.