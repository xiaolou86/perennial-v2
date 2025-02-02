// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import "../types/Registration.sol";

/// @title Strategy
/// @notice Logic for vault capital allocation
/// @dev - Deploys collateral first to satisfy the margin of each market, then deploys the rest by weight.
///      - Positions are then targeted based on the amount of collateral that ends up deployed to each market.
library StrategyLib {
    /// @dev The maximum multiplier that is allowed for leverage
    UFixed6 public constant LEVERAGE_BUFFER = UFixed6.wrap(1.2e6);

    /// @dev The context of an underlying market
    struct MarketContext {
        /// @dev The market parameter set
        MarketParameter marketParameter;

        /// @dev The risk parameter set
        RiskParameter riskParameter;

        /// @dev The local state of the vault
        Local local;

        /// @dev The vault's current account position
        Position currentAccountPosition;

        /// @dev The vault's latest account position
        Position latestAccountPosition;

        /// @dev The current global position
        Position currentPosition;

        /// @dev The latest valid price
        Fixed6 latestPrice;

        /// @dev The margin requirement of the vault
        UFixed6 margin;

        /// @dev The current closable amount of the vault
        UFixed6 closable;
    }

    /// @dev The target allocation for a market
    struct MarketTarget {
        /// @dev The amount of change in collateral
        Fixed6 collateral;

        /// @dev The new position
        UFixed6 position;
    }

    /// @dev Internal struct to avoid stack to deep error
    struct _AllocateLocals {
        UFixed6 marketCollateral;
        UFixed6 marketAssets;
        UFixed6 minPosition;
        UFixed6 maxPosition;
    }

    /// @notice Compute the target allocation for each market
    /// @param registrations The registrations of the markets
    /// @param collateral The amount of collateral to allocate
    /// @param assets The amount of collateral that is eligible for positions
    function allocate(
        Registration[] memory registrations,
        UFixed6 collateral,
        UFixed6 assets
    ) internal view returns (MarketTarget[] memory targets) {
        MarketContext[] memory contexts = new MarketContext[](registrations.length);
        for (uint256 marketId; marketId < registrations.length; marketId++)
            contexts[marketId] = _loadContext(registrations[marketId]);

        (uint256 totalWeight, UFixed6 totalMargin) = _aggregate(registrations, contexts);

        targets = new MarketTarget[](registrations.length);
        for (uint256 marketId; marketId < registrations.length; marketId++) {
            _AllocateLocals memory _locals;
            _locals.marketCollateral = contexts[marketId].margin
                .add(collateral.sub(totalMargin).muldiv(registrations[marketId].weight, totalWeight));

            _locals.marketAssets = assets
                .muldiv(registrations[marketId].weight, totalWeight)
                .min(_locals.marketCollateral.mul(LEVERAGE_BUFFER));

            UFixed6 minAssets = contexts[marketId].riskParameter.minMargin
                .unsafeDiv(registrations[marketId].leverage.mul(contexts[marketId].riskParameter.maintenance));
            if (contexts[marketId].marketParameter.closed || _locals.marketAssets.lt(minAssets))
                _locals.marketAssets = UFixed6Lib.ZERO;

            (_locals.minPosition, _locals.maxPosition) = _positionLimit(contexts[marketId]);

            (targets[marketId].collateral, targets[marketId].position) = (
                Fixed6Lib.from(_locals.marketCollateral).sub(contexts[marketId].local.collateral),
                _locals.marketAssets
                    .muldiv(registrations[marketId].leverage, contexts[marketId].latestPrice.abs())
                    .min(_locals.maxPosition)
                    .max(_locals.minPosition)
            );
        }
    }

    /// @notice Load the context of a market
    /// @param registration The registration of the market
    /// @return context The context of the market
    function _loadContext(Registration memory registration) private view returns (MarketContext memory context) {
        context.marketParameter = registration.market.parameter();
        context.riskParameter = registration.market.riskParameter();
        context.local = registration.market.locals(address(this));
        Global memory global = registration.market.global();
        context.latestPrice = global.latestPrice;

        // latest position
        UFixed6 previousClosable;
        previousClosable = _loadPosition(
            context,
            context.latestAccountPosition = registration.market.positions(address(this)),
            previousClosable
        );
        context.closable = context.latestAccountPosition.maker;

        // pending positions
        for (uint256 id = context.local.latestId + 1; id <= context.local.currentId; id++)
            previousClosable = _loadPosition(
                context,
                context.currentAccountPosition = registration.market.pendingPositions(address(this), id),
                previousClosable
            );

        // current position
        Position memory latestPosition = registration.market.position();
        context.currentPosition = registration.market.pendingPosition(global.currentId);
        context.currentPosition.adjust(latestPosition);
    }

    /// @notice Loads one position for the context calculation
    /// @param context The context of the market
    /// @param position The position to load
    /// @param previousMaker The previous maker position
    /// @return nextMaker The next maker position
    function _loadPosition(
        MarketContext memory context,
        Position memory position,
        UFixed6 previousMaker
    ) private pure returns (UFixed6 nextMaker) {
        position.adjust(context.latestAccountPosition);

        context.margin = position
            .margin(OracleVersion(0, context.latestPrice, true), context.riskParameter)
            .max(context.margin);
        context.closable = context.closable.sub(previousMaker.sub(position.maker.min(previousMaker)));
        nextMaker = position.maker;
    }

    /// @notice Aggregate the context of all markets
    /// @param registrations The registrations of the markets
    /// @param contexts The contexts of the markets
    /// @return totalWeight The total weight of all markets
    /// @return totalMargin The total margin of all markets
    function _aggregate(
        Registration[] memory registrations,
        MarketContext[] memory contexts
    ) private pure returns (uint256 totalWeight, UFixed6 totalMargin) {
        for (uint256 marketId; marketId < registrations.length; marketId++) {
            totalWeight += registrations[marketId].weight;
            totalMargin = totalMargin.add(contexts[marketId].margin);
        }
    }

    /// @notice Compute the position limit of a market
    /// @param context The context of the market
    /// @return The minimum position size before crossing the net position
    /// @return The maximum position size before crossing the maker limit
    function _positionLimit(MarketContext memory context) private pure returns (UFixed6, UFixed6) {
        return (
            // minimum position size before crossing the net position
            context.currentAccountPosition.maker.sub(
                context.currentPosition.maker
                    .sub(context.currentPosition.net().min(context.currentPosition.maker))
                    .min(context.currentAccountPosition.maker)
                    .min(context.closable)
            ),
            // maximum position size before crossing the maker limit
            context.currentAccountPosition.maker.add(
                context.riskParameter.makerLimit
                    .sub(context.currentPosition.maker.min(context.riskParameter.makerLimit))
            )
        );
    }
}
