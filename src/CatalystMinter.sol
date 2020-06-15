pragma solidity 0.6.5;
pragma experimental ABIEncoderV2;

import "./Interfaces/AssetToken.sol";
import "./contracts_common/src/Interfaces/ERC20.sol";
import "./Interfaces/ERC20Extended.sol";
import "./contracts_common/src/BaseWithStorage/MetaTransactionReceiver.sol";
import "./contracts_common/src/Libraries/SafeMathWithRequire.sol";
import "./Catalyst/GemToken.sol";
import "./Catalyst/CatalystToken.sol";
import "./CatalystRegistry.sol";


/// @notice Gateway to mint Asset with Catalyst, Gems and Sand
contract CatalystMinter is MetaTransactionReceiver {
    /// @dev emitted when fee collector (that receive the sand fee) get changed
    /// @param newCollector address of the new collector, address(0) means the fee will be burned
    event FeeCollector(address newCollector);

    function setFeeCollector(address newCollector) external {
        require(msg.sender == _admin, "NOT_AUTHORIZED_ADMIN");
        _setFeeCollector(newCollector);
    }

    /// @notice mint one Asset token.
    /// @param from address creating the Asset, need to be the tx sender or meta tx signer.
    /// @param packId unused packId that will let you predict the resulting tokenId.
    /// @param metadataHash cidv1 ipfs hash of the folder where 0.json file contains the metadata.
    /// @param catalystId address of the Catalyst ERC20 token to burn.
    /// @param gemIds list of gem ids to burn in the catalyst.
    /// @param to destination address receiving the minted tokens.
    /// @param data extra data.
    function mint(
        address from,
        uint40 packId,
        bytes32 metadataHash,
        uint256 catalystId,
        uint256[] calldata gemIds,
        uint256 quantity,
        address to,
        bytes calldata data
    ) external returns (uint256) {
        _checkAuthorization(from, to);
        _burnCatalyst(from, catalystId);
        uint16 maxGems = _checkQuantityAndBurnSandAndGems(from, catalystId, gemIds, quantity);
        uint256 id = _asset.mint(from, packId, metadataHash, quantity, 0, to, data);
        _catalystRegistry.setCatalyst(id, catalystId, maxGems, gemIds);
        return id;
    }

    /// @notice associate a catalyst to a fungible Asset token by extracting it as ERC721 first.
    /// @param from address from which the Asset token belongs to.
    /// @param assetId tokenId of the Asset being extracted.
    /// @param catalystId address of the catalyst token to use and burn.
    /// @param gemIds list of gems to socket into the catalyst (burned).
    /// @param to destination address receiving the extracted and upgraded ERC721 Asset token.
    function extractAndChangeCatalyst(
        address from,
        uint256 assetId,
        uint256 catalystId,
        uint256[] calldata gemIds,
        address to
    ) external returns (uint256 tokenId) {
        _checkAuthorization(from, to);
        tokenId = _asset.extractERC721From(from, assetId, from);
        _changeCatalyst(from, tokenId, catalystId, gemIds, to);
    }

    /// @notice associate a new catalyst to a non-fungible Asset token.
    /// @param from address from which the Asset token belongs to.
    /// @param assetId tokenId of the Asset being updated.
    /// @param catalystId address of the catalyst token to use and burn.
    /// @param gemIds list of gems to socket into the catalyst (burned).
    /// @param to destination address receiving the Asset token.
    function changeCatalyst(
        address from,
        uint256 assetId,
        uint256 catalystId,
        uint256[] calldata gemIds,
        address to
    ) external returns (uint256 tokenId) {
        _checkAuthorization(from, to);
        _changeCatalyst(from, assetId, catalystId, gemIds, to);
        return assetId;
    }

    /// @notice add gems to a fungible Asset token by extracting it as ERC721 first.
    /// @param from address from which the Asset token belongs to.
    /// @param assetId tokenId of the Asset being extracted.
    /// @param gemIds list of gems to socket into the existing catalyst (burned).
    /// @param to destination address receiving the extracted and upgraded ERC721 Asset token.
    function extractAndAddGems(
        address from,
        uint256 assetId,
        uint256[] calldata gemIds,
        address to
    ) external returns (uint256 tokenId) {
        _checkAuthorization(from, to);
        tokenId = _asset.extractERC721From(from, assetId, from);
        _addGems(from, tokenId, gemIds, to);
    }

    /// @notice add gems to a non-fungible Asset token.
    /// @param from address from which the Asset token belongs to.
    /// @param assetId tokenId of the Asset to which the gems will be added to.
    /// @param gemIds list of gems to socket into the existing catalyst (burned).
    /// @param to destination address receiving the extracted and upgraded ERC721 Asset token.
    function addGems(
        address from,
        uint256 assetId,
        uint256[] calldata gemIds,
        address to
    ) external {
        _checkAuthorization(from, to);
        _addGems(from, assetId, gemIds, to);
    }

    struct AssetData {
        uint256[] gemIds;
        uint256 quantity;
        uint256 catalystId;
    }

    // /// @notice mint multiple Asset tokens.
    // /// @param from address creating the Asset, need to be the tx sender or meta tx signer.
    // /// @param packId unused packId that will let you predict the resulting tokenId.
    // /// @param metadataHash cidv1 ipfs hash of the folder where 0.json file contains the metadata.
    // /// @param assets contains the data to associate catalyst and gems to the assets.
    // /// @param to destination address receiving the minted tokens.
    // /// @param data extra data.
    // function mintMultipleWithoutQuantities(
    //     address from,
    //     uint40 packId,
    //     bytes32 metadataHash,
    //     AssetData[] memory assets,
    //     address to,
    //     bytes memory data
    // ) public returns (uint256[] memory ids) {
    //     require(assets.length > 0, "0 assets passed in");
    //     _checkAuthorization(from, to);
    //     return _mintMultipleWithoutQuantities(from, packId, metadataHash, gemsQuantities, catalystsQuantities, assets, to, data);
    // }

    /// @notice mint multiple Asset tokens.
    /// @param from address creating the Asset, need to be the tx sender or meta tx signer.
    /// @param packId unused packId that will let you predict the resulting tokenId.
    /// @param metadataHash cidv1 ipfs hash of the folder where 0.json file contains the metadata.
    /// @param gemsQuantities quantities of gems to be used for each id in order
    /// @param catalystsQuantities quantities of catalyst to be used for each id in order
    /// @param assets contains the data to associate catalyst and gems to the assets.
    /// @param to destination address receiving the minted tokens.
    /// @param data extra data.
    function mintMultiple(
        address from,
        uint40 packId,
        bytes32 metadataHash,
        uint256[] memory gemsQuantities,
        uint256[] memory catalystsQuantities,
        AssetData[] memory assets,
        address to,
        bytes memory data
    ) public returns (uint256[] memory ids) {
        require(assets.length > 0, "0 assets passed in");
        _checkAuthorization(from, to);
        return _mintMultiple(from, packId, metadataHash, gemsQuantities, catalystsQuantities, assets, to, data);
    }

    // //////////////////// INTERNALS ////////////////////

    function _checkQuantityAndBurnSandAndGems(
        address from,
        uint256 catalystId,
        uint256[] memory gemIds,
        uint256 quantity
    ) internal returns (uint16) {
        (uint16 maxGems, uint16 minQuantity, uint16 maxQuantity, uint256 sandFee) = _catalysts.getMintData(catalystId);
        require(minQuantity <= quantity && quantity <= maxQuantity, "invalid quantity");
        require(gemIds.length <= maxGems, "too many gems");
        _burnSingleGems(from, gemIds);
        _chargeSand(from, quantity * sandFee); // TODO safe math
        return maxGems;
    }

    function _mintMultiple(
        address from,
        uint40 packId,
        bytes32 metadataHash,
        uint256[] memory gemsQuantities,
        uint256[] memory catalystsQuantities,
        AssetData[] memory assets,
        address to,
        bytes memory data
    ) internal returns (uint256[] memory ids) {
        (uint256 totalSandFee, uint256[] memory supplies, uint16[] memory maxGemsList) = _handleMultipleCatalysts(
            from,
            gemsQuantities,
            catalystsQuantities,
            assets
        );

        _chargeSand(from, totalSandFee);

        return _mintAssets(from, packId, metadataHash, assets, supplies, maxGemsList, to, data);
    }

    function _chargeSand(address from, uint256 sandFee) internal {
        address feeCollector = _feeCollector;
        if (feeCollector != address(0) && sandFee > 0) {
            if (feeCollector == address(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF)) {
                // special address for burn
                _sand.burnFor(from, sandFee);
            } else {
                _sand.transferFrom(from, _feeCollector, sandFee); // TODO Safe math
            }
        }
    }

    function _handleMultipleCatalysts(
        address from,
        uint256[] memory gemsQuantities,
        uint256[] memory catalystsQuantities,
        AssetData[] memory assets
    )
        internal
        returns (
            uint256 totalSandFee,
            uint256[] memory supplies,
            uint16[] memory maxGemsList
        )
    {
        _burnCatalysts(from, catalystsQuantities);
        _burnGems(from, gemsQuantities);

        totalSandFee = 0;
        supplies = new uint256[](assets.length);
        maxGemsList = new uint16[](assets.length);

        for (uint256 i = 0; i < assets.length; i++) {
            require(catalystsQuantities[assets[i].catalystId] > 0, "invalid catalys quantities");
            catalystsQuantities[assets[i].catalystId]--;
            gemsQuantities = _checkGemsQuantities(gemsQuantities, assets[i].gemIds);
            (uint16 maxGems, uint16 minQuantity, uint16 maxQuantity, uint256 sandFee) = _catalysts.getMintData(assets[i].catalystId); // TODO hardcode
            maxGemsList[i] = maxGems;
            require(minQuantity <= assets[i].quantity && assets[i].quantity <= maxQuantity, "invalid quantity");
            supplies[i] = assets[i].quantity;
            totalSandFee += sandFee * assets[i].quantity;
            require(assets[i].gemIds.length <= maxGems, "too many gems for catalyst");
        }
    }

    function _checkGemsQuantities(uint256[] memory gemsQuantities, uint256[] memory gemIds) internal pure returns (uint256[] memory) {
        for (uint256 i = 0; i < gemIds.length; i++) {
            require(gemsQuantities[gemIds[i]] > 0, "invalid gem quantities");
            gemsQuantities[gemIds[i]]--;
        }
        return gemsQuantities;
    }

    function _burnCatalysts(address from, uint256[] memory catalystsQuantities) internal {
        uint256[] memory ids = new uint256[](catalystsQuantities.length);
        for (uint256 i = 0; i < ids.length; i++) {
            ids[i] = i;
        }
        _catalysts.batchBurnFrom(from, ids, catalystsQuantities);
    }

    function _burnGems(address from, uint256[] memory gemsQuantities) internal {
        uint256[] memory ids = new uint256[](gemsQuantities.length);
        for (uint256 i = 0; i < ids.length; i++) {
            ids[i] = i;
        }
        _gems.batchBurnFrom(from, ids, gemsQuantities);
    }

    function _mintAssets(
        address from,
        uint40 packId,
        bytes32 metadataHash,
        AssetData[] memory assets,
        uint256[] memory supplies,
        uint16[] memory maxGemsList,
        address to,
        bytes memory data
    ) internal returns (uint256[] memory tokenIds) {
        tokenIds = _asset.mintMultiple(from, packId, metadataHash, supplies, "", to, data);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            AssetData memory asset = assets[i];
            _catalystRegistry.setCatalyst(tokenIds[i], asset.catalystId, maxGemsList[i], asset.gemIds);
        }
    }

    function _changeCatalyst(
        address from,
        uint256 assetId,
        uint256 catalystId,
        uint256[] memory gemIds,
        address to
    ) internal {
        require(assetId & IS_NFT > 0, "NEED TO BE AN NFT"); // Asset (ERC1155ERC721.sol) ensure NFT will return true here and non-NFT will reyrn false
        _burnCatalyst(from, catalystId);
        (uint16 maxGems, , , ) = _catalysts.getMintData(catalystId);
        require(gemIds.length <= maxGems, "too many gems");
        _burnGems(from, gemIds);

        _catalystRegistry.setCatalyst(assetId, catalystId, maxGems, gemIds);

        _transfer(from, to, assetId);
    }

    function _addGems(
        address from,
        uint256 assetId,
        uint256[] memory gemIds,
        address to
    ) internal {
        require(assetId & IS_NFT > 0, "NEED TO BE AN NFT"); // Asset (ERC1155ERC721.sol) ensure NFT will return true here and non-NFT will reyrn false
        _catalystRegistry.addGems(assetId, gemIds);
        _transfer(from, to, assetId);
    }

    function _transfer(
        address from,
        address to,
        uint256 assetId
    ) internal {
        if (from != to) {
            _asset.safeTransferFrom(from, to, assetId);
        }
    }

    function _checkAuthorization(address from, address to) internal view {
        require(to != address(0), "INVALID ADDRESS ZERO");
        require(from == msg.sender || _metaTransactionContracts[msg.sender], "not authorized");
    }

    function _burnSingleGems(address from, uint256[] memory gemIds) internal {
        // TODO use extra array in calldata to group gemIds
        uint256[] memory amounts = new uint256[](gemIds.length);
        for (uint256 i = 0; i < gemIds.length; i++) {
            amounts[i] = 1;
        }
        _gems.batchBurnFrom(from, gemIds, amounts);
    }

    function _burnCatalyst(address from, uint256 catalystId) internal {
        _catalysts.burnFrom(from, catalystId, 1);
    }

    function _setFeeCollector(address newCollector) internal {
        _feeCollector = newCollector;
        emit FeeCollector(newCollector);
    }

    // /////////////////// UTILITIES /////////////////////
    using SafeMathWithRequire for uint256;

    // //////////////////////// DATA /////////////////////
    uint256 private constant IS_NFT = 0x0000000000000000000000000000000000000000800000000000000000000000;

    ERC20Extended immutable _sand;
    AssetToken immutable _asset;
    GemToken immutable _gems;
    CatalystToken immutable _catalysts;
    CatalystRegistry immutable _catalystRegistry;
    address _feeCollector;

    // /////////////////// CONSTRUCTOR ////////////////////
    constructor(
        CatalystRegistry catalystRegistry,
        ERC20Extended sand,
        AssetToken asset,
        GemToken gems,
        address metaTx,
        address admin,
        address feeCollector,
        CatalystToken catalysts
    ) public {
        _catalystRegistry = catalystRegistry;
        _sand = sand;
        _asset = asset;
        _gems = gems;
        _catalysts = catalysts;
        _admin = admin;
        _setFeeCollector(feeCollector);
        _setMetaTransactionProcessor(metaTx, true);
    }
}
