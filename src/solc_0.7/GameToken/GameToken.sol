//SPDX-License-Identifier: MIT
pragma solidity 0.7.5;
pragma experimental ABIEncoderV2;

import "../common/BaseWithStorage/ERC721BaseToken.sol";
import "../common/BaseWithStorage/WithMinter.sol";
import "../common/Interfaces/AssetToken.sol";
import "../common/Interfaces/IGameToken.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract GameToken is ERC721BaseToken, WithMinter, IGameToken {
    ///////////////////////////////  Libs //////////////////////////////

    using SafeMath for uint256;

    ///////////////////////////////  Data //////////////////////////////

    AssetToken internal immutable _asset;

    bytes4 private constant ERC1155_RECEIVED = 0xf23a6e61;
    bytes4 private constant ERC1155_BATCH_RECEIVED = 0xbc197c81;
    uint256 private constant CREATOR_OFFSET_MULTIPLIER = uint256(2)**(256 - 160);

    mapping(uint256 => mapping(uint256 => uint256)) private _gameAssets;
    mapping(address => address) private _creatorship; // creatorship transfer

    mapping(uint256 => string) private _metaData;
    mapping(uint256 => mapping(address => bool)) private _gameEditors;

    ///////////////////////////////  Events //////////////////////////////

    event AssetsAdded(uint256 indexed id, uint256[] assets, uint256[] values);
    event AssetsRemoved(uint256 indexed id, uint256[] assets, uint256[] values, address to);
    event CreatorshipTransfer(address indexed original, address indexed from, address indexed to);
    event GameEditorSet(uint256 indexed id, address gameEditor, bool isEditor);

    constructor(
        address metaTransactionContract,
        address admin,
        AssetToken asset,
        address initialMinter
    ) ERC721BaseToken(metaTransactionContract, admin) {
        _asset = asset;
        _minter = initialMinter;
    }

    ///////////////////////////////  Modifiers //////////////////////////////

    modifier notToZero(address to) {
        require(to != address(0), "DESTINATION_ZERO_ADDRESS");
        _;
    }

    modifier notToThis(address to) {
        require(to != address(this), "DESTINATION_GAME_CONTRACT");
        _;
    }

    ///////////////////////////////  Functions //////////////////////////////

    /// @notice Function to get the amount of each assetId in a GAME
    /// @param gameId The game to query
    /// @param assetIds The assets to get balances for
    function getAssetBalances(uint256 gameId, uint256[] calldata assetIds)
        external
        view
        override
        returns (uint256[] memory)
    {
        uint256 length = assetIds.length;
        uint256[] memory assets;
        assets = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            assets[i] = _gameAssets[gameId][assetIds[i]];
        }
        return assets;
    }

    /// @notice Function to allow token owner to set game editors
    /// @param from The address of the one creating the game (may be different from msg.sender if metaTx)
    /// @param gameId The id of the GAME token owned by owner
    /// @param editor The address of the editor to set
    /// @param isEditor Add or remove the ability to edit
    function setGameEditor(
        address from,
        uint256 gameId,
        address editor,
        bool isEditor
    ) external override {
        require(msg.sender == _ownerOf(gameId) || _isValidMetaTx(from), "EDITOR_ACCESS_DENIED");
        _setGameEditor(gameId, editor, isEditor);
    }

    /// @dev Function to allow token owner to set game editors
    /// @param gameId The id of the GAME token owned by owner
    /// @param editor The address of the editor to set
    /// @param isEditor Add or remove the ability to edit
    function _setGameEditor(
        uint256 gameId,
        address editor,
        bool isEditor
    ) internal {
        emit GameEditorSet(gameId, editor, isEditor);
        _gameEditors[gameId][editor] = isEditor;
    }

    /// @notice Transfers creatorship of `original` from `sender` to `to`.
    /// @param sender address of current registered creator.
    /// @param original address of the original creator whose creation are saved in the ids themselves.
    /// @param to address which will be given creatorship for all tokens originally minted by `original`.
    function transferCreatorship(
        address sender,
        address original,
        address to
    ) external override notToZero(to) {
        require(
            msg.sender == sender || _isValidMetaTx(sender) || _superOperators[msg.sender],
            "TRANSFER_ACCESS_DENIED"
        );
        require(sender != address(0), "ZERO_SENDER_FORBIDDEN");
        address current = _creatorship[original];
        if (current == address(0)) {
            current = original;
        }
        require(current != to, "CURRENT_=_TO");
        require(current == sender, "CURRENT_!=_SENDER");
        if (to == original) {
            _creatorship[original] = address(0);
        } else {
            _creatorship[original] = to;
        }
        emit CreatorshipTransfer(original, current, to);
    }

    /// @notice Function to create a new GAME token
    /// @param from The address of the one creating the game (may be different from msg.sender if metaTx)
    /// @param to The address who will be assigned ownership of this game
    /// @param assetIds The ids of the assets to add to this game
    /// @param values the amount of each token id to add to game
    /// @param editor The address to allow to edit (can also be set later)
    /// @param randomId A random id created on the backend.
    /// @return id The id of the new GAME token (erc721)
    function createGame(
        address from,
        address to,
        uint256[] memory assetIds,
        uint256[] memory values,
        address editor,
        string memory uri,
        uint96 randomId
    ) external override onlyMinter() notToZero(to) notToThis(to) returns (uint256 id) {
        uint256 gameId = _mintGame(from, to, randomId);

        if (editor != address(0)) {
            _setGameEditor(gameId, editor, true);
        }

        if (assetIds.length != 0) {
            addAssets(from, gameId, assetIds, values, uri);
        }

        _setTokenURI(gameId, uri);
        return gameId;
    }

    /// @notice Function to get game editor status
    /// @param gameId The id of the GAME token owned by owner
    /// @param editor The address of the editor to set
    /// @return isEditor Editor status of editor for given tokenId
    function isGameEditor(uint256 gameId, address editor) external view override returns (bool isEditor) {
        return _gameEditors[gameId][editor];
    }

    function onERC1155BatchReceived(
        address operator,
        address, /*from*/
        uint256[] calldata, /*ids*/
        uint256[] calldata, /*values*/
        bytes calldata /*data*/
    ) external view override returns (bytes4) {
        if (operator == address(this)) {
            return ERC1155_BATCH_RECEIVED;
        }
        revert("ERC1155_BATCH_REJECTED");
    }

    function onERC1155Received(
        address operator,
        address, /*from*/
        uint256, /*id*/
        uint256, /*value*/
        bytes calldata /*data*/
    ) external view override returns (bytes4) {
        if (operator == address(this)) {
            return ERC1155_RECEIVED;
        }
        revert("ERC1155_REJECTED");
    }

    /// @notice Return the name of the token contract
    /// @return The name of the token contract
    function name() external pure override returns (string memory) {
        return "The Sandbox: GAME token";
    }

    /// @notice Function to get the symbol of the token contract
    /// @return The symbol of the token contract
    function symbol() external pure override returns (string memory) {
        return "GAME";
    }

    /// @notice Set the URI of a specific game token
    /// @param gameId The id of the game token
    /// @param URI The URI string for the token's metadata
    function setTokenURI(uint256 gameId, string calldata URI) external override onlyMinter() {
        _setTokenURI(gameId, URI);
    }

    /// @notice Function to burn a GAME token and recover assets
    /// @param from The address of the one destroying the game
    /// @param to The address to send all GAME assets to
    /// @param gameId The id of the GAME to destroy
    /// @param assetIds The assets to recover from the burnt GAME
    function destroyAndRecover(
        address from,
        address to,
        uint256 gameId,
        uint256[] calldata assetIds
    ) external override {
        _destroyGame(from, to, gameId);
        _recoverAssets(from, to, gameId, assetIds);
    }

    /// @notice Function to burn a GAME token
    /// @param from The address of the one destroying the game
    /// @param to The address to send all GAME assets to
    /// @param gameId The id of the GAME to destroy
    function destroyGame(
        address from,
        address to,
        uint256 gameId
    ) external override {
        _destroyGame(from, to, gameId);
    }

    /// @notice Function to add assets to an existing GAME
    /// @param from The address of the current owner of assets
    /// @param gameId The id of the GAME to add asset to
    /// @param assetIds The id of the asset to add to GAME
    /// @param values The amount of each asset to add to GAME
    /// @param uri The new uri to set
    function addAssets(
        address from,
        uint256 gameId,
        uint256[] memory assetIds,
        uint256[] memory values,
        string memory uri
    ) public override onlyMinter() {
        require(assetIds.length == values.length && assetIds.length != 0, "INVALID_INPUT_LENGTHS");
        for (uint256 i = 0; i < assetIds.length; i++) {
            uint256 currentValue = _gameAssets[gameId][assetIds[i]];
            require(values[i] != 0, "INVALID_ASSET_ADDITION");
            _gameAssets[gameId][assetIds[i]] = currentValue.add(values[i]);
        }
        if (assetIds.length == 1) {
            _asset.safeTransferFrom(from, address(this), assetIds[0], values[0], "");
        } else {
            _asset.safeBatchTransferFrom(from, address(this), assetIds, values, "");
        }
        _setTokenURI(gameId, uri);
        emit AssetsAdded(gameId, assetIds, values);
    }

    /// @notice Function to remove assets from a GAME
    /// @param gameId The GAME to remove assets from
    /// @param assetIds An array of asset Ids to remove
    /// @param values An array of the number of each asset id to remove
    /// @param to The address to send removed assets to
    /// @param uri The URI string to update the GAME token's URI

    function removeAssets(
        uint256 gameId,
        uint256[] memory assetIds,
        uint256[] memory values,
        address to,
        string memory uri
    ) public override onlyMinter() notToZero(to) {
        require(assetIds.length == values.length && assetIds.length != 0, "INVALID_INPUT_LENGTHS");

        for (uint256 i = 0; i < assetIds.length; i++) {
            uint256 currentValue = _gameAssets[gameId][assetIds[i]];
            require(currentValue != 0 && values[i] != 0 && values[i] <= currentValue, "INVALID_ASSET_REMOVAL");
            _gameAssets[gameId][assetIds[i]] = currentValue.sub(values[i]);
        }

        if (assetIds.length == 1) {
            _asset.safeTransferFrom(address(this), to, assetIds[0], values[0], "");
        } else {
            _asset.safeBatchTransferFrom(address(this), to, assetIds, values, "");
        }

        _setTokenURI(gameId, uri);
        emit AssetsRemoved(gameId, assetIds, values, to);
    }

    /// @notice Get the creator of the token type `id`.
    /// @param id the id of the token to get the creator of.
    /// @return the creator of the token type `id`.
    function creatorOf(uint256 id) public view override returns (address) {
        require(id != uint256(0), "GAME_NEVER_MINTED");
        address originalCreator = address(id / CREATOR_OFFSET_MULTIPLIER);
        address newCreator = _creatorship[originalCreator];
        if (newCreator != address(0)) {
            return newCreator;
        }
        return originalCreator;
    }

    /// @notice Return the URI of a specific token
    /// @param gameId The id of the token
    /// @return uri The URI of the token
    function tokenURI(uint256 gameId) public view override returns (string memory uri) {
        require(_ownerOf(gameId) != address(0), "BURNED_OR_NEVER_MINTED");
        string memory URI = _metaData[gameId];
        return URI;
    }

    /// @notice Function to transfer assets from a burnt GAME
    /// @param from Previous owner of the burnt game
    /// @param to Address that will receive the assets
    /// @param gameId Id of the burnt GAME token
    /// @param assetIds The assets to recover from the burnt GAME
    function recoverAssets(
        address from,
        address to,
        uint256 gameId,
        uint256[] memory assetIds
    ) public override {
        _recoverAssets(from, to, gameId, assetIds);
    }

    /**
     * @notice Check if the contract supports an interface
     * 0x01ffc9a7 is ERC-165
     * 0x80ac58cd is ERC-721
     * @param id The id of the interface
     * @return True if the interface is supported
     */
    function supportsInterface(bytes4 id) public pure override returns (bool) {
        return id == 0x01ffc9a7 || id == 0x80ac58cd || id == 0x5b5e139f;
    }

    function _setTokenURI(uint256 gameId, string memory URI) internal {
        _metaData[gameId] = URI;
    }

    function _destroyGame(
        address from,
        address to,
        uint256 gameId
    ) internal notToZero(to) notToThis(to) {
        address owner = _ownerOf(gameId);
        require(msg.sender == owner || _isValidMetaTx(from), "DESTROY_ACCESS_DENIED");
        require(from == owner, "DESTROY_INVALID_FROM");
        delete _metaData[gameId];
        _creatorship[creatorOf(gameId)] = address(0);
        _burn(from, owner, gameId);
    }

    function _recoverAssets(
        address from,
        address to,
        uint256 gameId,
        uint256[] memory assetIds
    ) internal notToZero(to) notToThis(to) {
        bool validMetaTx = _isValidMetaTx(from);
        if (!validMetaTx) {
            require(from == msg.sender, "INVALID_RECOVERY_CALLER");
            _check_withdrawal_authorized(from, gameId);
        }
        require(assetIds.length > 0, "WITHDRAWAL_COMPLETE");
        uint256[] memory values;
        values = new uint256[](assetIds.length);
        for (uint256 i = 0; i < assetIds.length; i++) {
            values[i] = _gameAssets[gameId][assetIds[i]];
            delete _gameAssets[gameId][assetIds[i]];
        }

        _asset.safeBatchTransferFrom(address(this), to, assetIds, values, "");
        emit AssetsRemoved(gameId, assetIds, values, to);
    }

    function _check_withdrawal_authorized(address from, uint256 gameId) internal view {
        require(from != address(0), "SENDER_ZERO_ADDRESS");
        require(from == _withdrawalOwnerOf(gameId), "LAST_OWNER_NOT_EQUAL_SENDER");
    }

    function _withdrawalOwnerOf(uint256 id) internal view returns (address) {
        uint256 data = _owners[id];
        if ((data & (2**160)) == 2**160) {
            return address(data);
        }
        return address(0);
    }

    /// @dev Function to create a new gameId and associate it with an owner
    /// @param from The address of the Game creator
    /// @param to The address of the Game owner
    /// @param randomId The id to use when generating the new GameId
    /// @return id The newly created gameId
    function _mintGame(
        address from,
        address to,
        uint96 randomId
    ) internal returns (uint256 id) {
        uint256 gameId = generateGameId(from, randomId);
        _owners[gameId] = uint256(to);
        _numNFTPerAddress[to]++;
        emit Transfer(address(0), to, gameId);
        return gameId;
    }

    /// @dev Function to create a new gameId and associate it with an owner
    /// @param creator The address of the Game creator
    /// @param randomId The id to use when generating the new GameId
    function generateGameId(address creator, uint96 randomId) internal pure returns (uint256) {
        return uint256(creator) * CREATOR_OFFSET_MULTIPLIER + uint96(randomId);
    }
}
