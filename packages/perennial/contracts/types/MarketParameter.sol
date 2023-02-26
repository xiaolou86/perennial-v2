// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import "@equilibria/perennial-v2-payoff/contracts/IPayoffProvider.sol";
import "@equilibria/perennial-v2-oracle/contracts/IOracleProvider.sol";
import "@equilibria/root-v2/contracts/UFixed6.sol";
import "@equilibria/root-v2/contracts/UJumpRateUtilizationCurve6.sol";
import "./Payoff.sol";

/// @dev MarketParameter type
struct MarketParameter {
    UFixed6 maintenance;    // <= 429496%
    UFixed6 fundingFee;     // <= 429496%
    UFixed6 takerFee;       // <= 429496%
    UFixed6 positionFee;    // <= 429496%
    UFixed6 makerLiquidity; // <= 429496%
    UFixed6 makerLimit;     // <= 18.45tn
    bool closed;
    UFixed6 makerRewardRate;
    UFixed6 longRewardRate;
    UFixed6 shortRewardRate;
    UJumpRateUtilizationCurve6 utilizationCurve;
    IOracleProvider oracle;
    Payoff payoff;
}
struct StoredMarketParameter {
    /* slot 1 */
    address oracle;
    uint24 maintenance; // <= 1677%
    uint24 fundingFee;  // <= 1677%
    uint24 takerFee;    // <= 1677%
    uint24 positionFee; // <= 1677%

    /* slot 2 */
    address payoffProvider;
    uint32 makerRewardRate;  // <= 2147.48 / s
    uint32 longRewardRate;   // <= 2147.48 / s
    uint32 shortRewardRate;  // <= 2147.48 / s

    /* slot 3 */
    uint24 makerLiquidity;                    // <= 1677%
    uint48 makerLimit;                        // <= 281m
    uint32 utilizationCurveMinRate;           // <= 214748%
    uint32 utilizationCurveMaxRate;           // <= 214748%
    uint32 utilizationCurveTargetRate;        // <= 214748%
    uint24 utilizationCurveTargetUtilization; // <= 1677%
    bool closed;
    bool payoffShort;
    bool fuse;
    bytes5 __unallocated0__;
}
struct MarketParameterStorage { StoredMarketParameter value; }
using MarketParameterStorageLib for MarketParameterStorage global;

library MarketParameterStorageLib {
    error MarketParameterStorageInvalidError();
    error MarketParameterStorageImmutableError();

    function read(MarketParameterStorage storage self) internal view returns (MarketParameter memory) {
        StoredMarketParameter memory value = self.value;
        return MarketParameter(
            UFixed6.wrap(uint256(value.maintenance)),
            UFixed6.wrap(uint256(value.fundingFee)),
            UFixed6.wrap(uint256(value.takerFee)),
            UFixed6.wrap(uint256(value.positionFee)),
            UFixed6.wrap(uint256(value.makerLiquidity)),
            UFixed6.wrap(uint256(value.makerLimit)),
            value.closed,
            UFixed6.wrap(uint256(value.makerRewardRate)),
            UFixed6.wrap(uint256(value.longRewardRate)),
            UFixed6.wrap(uint256(value.shortRewardRate)),
            UJumpRateUtilizationCurve6(
                UFixed6.wrap(uint256(value.utilizationCurveMinRate)),
                UFixed6.wrap(uint256(value.utilizationCurveMaxRate)),
                UFixed6.wrap(uint256(value.utilizationCurveTargetRate)),
                UFixed6.wrap(uint256(value.utilizationCurveTargetUtilization))
            ),
            IOracleProvider(value.oracle),
            Payoff(IPayoffProvider(value.payoffProvider), value.payoffShort)
        );
    }

    function store(MarketParameterStorage storage self, MarketParameter memory newValue) internal {
        StoredMarketParameter memory oldValue = self.value;

        if (newValue.maintenance.gt(UFixed6Lib.MAX_24)) revert MarketParameterStorageInvalidError();
        if (newValue.fundingFee.gt(UFixed6Lib.MAX_24)) revert MarketParameterStorageInvalidError();
        if (newValue.takerFee.gt(UFixed6Lib.MAX_24)) revert MarketParameterStorageInvalidError();
        if (newValue.positionFee.gt(UFixed6Lib.MAX_24)) revert MarketParameterStorageInvalidError();
        if (newValue.makerLiquidity.gt(UFixed6Lib.MAX_24)) revert MarketParameterStorageInvalidError();
        if (newValue.makerLimit.gt(UFixed6Lib.MAX_48)) revert MarketParameterStorageInvalidError();
        if (newValue.makerRewardRate.gt(UFixed6Lib.MAX_32)) revert MarketParameterStorageInvalidError();
        if (newValue.longRewardRate.gt(UFixed6Lib.MAX_32)) revert MarketParameterStorageInvalidError();
        if (newValue.shortRewardRate.gt(UFixed6Lib.MAX_32)) revert MarketParameterStorageInvalidError();
        if (newValue.utilizationCurve.minRate.gt(UFixed6Lib.MAX_32)) revert MarketParameterStorageInvalidError();
        if (newValue.utilizationCurve.maxRate.gt(UFixed6Lib.MAX_32)) revert MarketParameterStorageInvalidError();
        if (newValue.utilizationCurve.targetRate.gt(UFixed6Lib.MAX_32)) revert MarketParameterStorageInvalidError();
        if (newValue.utilizationCurve.targetUtilization.gt(UFixed6Lib.MAX_32)) revert MarketParameterStorageInvalidError();

        if (oldValue.fuse && address(newValue.oracle) != oldValue.oracle) revert MarketParameterStorageImmutableError();
        if (oldValue.fuse && address(newValue.payoff.provider) != oldValue.payoffProvider) revert MarketParameterStorageImmutableError();
        if (oldValue.fuse && newValue.payoff.short != oldValue.payoffShort) revert MarketParameterStorageImmutableError();

        self.value = StoredMarketParameter({
            maintenance: uint24(UFixed6.unwrap(newValue.maintenance)),
            fundingFee: uint24(UFixed6.unwrap(newValue.fundingFee)),
            takerFee: uint24(UFixed6.unwrap(newValue.takerFee)),
            positionFee: uint24(UFixed6.unwrap(newValue.positionFee)),
            makerLiquidity: uint24(UFixed6.unwrap(newValue.makerLiquidity)),
            makerLimit: uint48(UFixed6.unwrap(newValue.makerLimit)),
            closed: newValue.closed,
            makerRewardRate: uint32(UFixed6.unwrap(newValue.makerRewardRate)),
            longRewardRate: uint32(UFixed6.unwrap(newValue.longRewardRate)),
            shortRewardRate: uint32(UFixed6.unwrap(newValue.shortRewardRate)),
            utilizationCurveMinRate: uint32(UFixed6.unwrap(newValue.utilizationCurve.minRate)),
            utilizationCurveMaxRate: uint32(UFixed6.unwrap(newValue.utilizationCurve.maxRate)),
            utilizationCurveTargetRate: uint32(UFixed6.unwrap(newValue.utilizationCurve.targetRate)),
            utilizationCurveTargetUtilization: uint24(UFixed6.unwrap(newValue.utilizationCurve.targetUtilization)),
            oracle: address(newValue.oracle),
            payoffProvider: address(newValue.payoff.provider),
            payoffShort: newValue.payoff.short,
            fuse: true,
            __unallocated0__: bytes5(0)
        });
    }
}