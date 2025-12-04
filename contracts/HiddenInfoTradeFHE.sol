// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { FHE, euint32, ebool, euint64 } from "@fhevm/solidity/lib/FHE.sol";
import { SepoliaConfig } from "@fhevm/solidity/config/ZamaConfig.sol";

contract HiddenInfoTradeFHE is SepoliaConfig {
    struct EncryptedGameState {
        uint256 id;
        address player;
        euint32 encryptedPosition;
        euint32 encryptedResources;
        euint32 encryptedStrategy;
        uint256 timestamp;
    }

    struct EncryptedInfoTrade {
        uint256 id;
        address seller;
        address buyer;
        euint32 encryptedInfoType;
        euint32 encryptedInfoContent;
        euint32 encryptedPrice;
        bool isRevealed;
    }

    uint256 public gameStateCount;
    uint256 public tradeCount;
    mapping(uint256 => EncryptedGameState) public gameStates;
    mapping(uint256 => EncryptedInfoTrade) public infoTrades;
    
    mapping(uint256 => uint256) private requestToTrade;
    mapping(address => bool) public registeredPlayers;

    event GameStateUpdated(uint256 indexed id, address indexed player);
    event TradeCreated(uint256 indexed id, address indexed seller);
    event TradeCompleted(uint256 indexed id);
    event TradeRevealed(uint256 indexed id);

    modifier onlyPlayer() {
        require(registeredPlayers[msg.sender], "Not registered player");
        _;
    }

    /// @notice Register as a game player
    function registerPlayer() public {
        registeredPlayers[msg.sender] = true;
    }

    /// @notice Update encrypted game state
    function updateGameState(
        euint32 position,
        euint32 resources,
        euint32 strategy
    ) public onlyPlayer {
        gameStateCount++;
        gameStates[gameStateCount] = EncryptedGameState({
            id: gameStateCount,
            player: msg.sender,
            encryptedPosition: position,
            encryptedResources: resources,
            encryptedStrategy: strategy,
            timestamp: block.timestamp
        });

        emit GameStateUpdated(gameStateCount, msg.sender);
    }

    /// @notice Create encrypted information trade
    function createInfoTrade(
        address buyer,
        euint32 infoType,
        euint32 infoContent,
        euint32 price
    ) public onlyPlayer {
        tradeCount++;
        infoTrades[tradeCount] = EncryptedInfoTrade({
            id: tradeCount,
            seller: msg.sender,
            buyer: buyer,
            encryptedInfoType: infoType,
            encryptedInfoContent: infoContent,
            encryptedPrice: price,
            isRevealed: false
        });

        emit TradeCreated(tradeCount, msg.sender);
    }

    /// @notice Complete information trade
    function completeTrade(uint256 tradeId) public onlyPlayer {
        EncryptedInfoTrade storage trade = infoTrades[tradeId];
        require(trade.buyer == msg.sender, "Not trade buyer");
        require(!trade.isRevealed, "Already revealed");

        bytes32[] memory ciphertexts = new bytes32[](3);
        ciphertexts[0] = FHE.toBytes32(trade.encryptedInfoType);
        ciphertexts[1] = FHE.toBytes32(trade.encryptedInfoContent);
        ciphertexts[2] = FHE.toBytes32(trade.encryptedPrice);

        uint256 reqId = FHE.requestDecryption(ciphertexts, this.processTrade.selector);
        requestToTrade[reqId] = tradeId;
    }

    /// @notice Process trade information
    function processTrade(
        uint256 requestId,
        bytes memory cleartexts,
        bytes memory proof
    ) public {
        uint256 tradeId = requestToTrade[requestId];
        require(tradeId != 0, "Invalid request");

        FHE.checkSignatures(requestId, cleartexts, proof);

        uint32[] memory values = abi.decode(cleartexts, (uint32[]));
        
        // Update game state based on trade (simplified example)
        infoTrades[tradeId].isRevealed = true;
        
        emit TradeCompleted(tradeId);
    }

    /// @notice Request trade reveal
    function requestTradeReveal(uint256 tradeId) public onlyPlayer {
        EncryptedInfoTrade storage trade = infoTrades[tradeId];
        require(trade.seller == msg.sender || trade.buyer == msg.sender, "Not trade participant");
        require(!trade.isRevealed, "Already revealed");

        bytes32[] memory ciphertexts = new bytes32[](1);
        ciphertexts[0] = FHE.toBytes32(trade.encryptedInfoContent);

        uint256 reqId = FHE.requestDecryption(ciphertexts, this.finalizeReveal.selector);
        requestToTrade[reqId] = tradeId;
    }

    /// @notice Finalize trade reveal
    function finalizeReveal(
        uint256 requestId,
        bytes memory cleartexts,
        bytes memory proof
    ) public {
        uint256 tradeId = requestToTrade[requestId];
        require(tradeId != 0, "Invalid request");

        FHE.checkSignatures(requestId, cleartexts, proof);

        infoTrades[tradeId].isRevealed = true;
        emit TradeRevealed(tradeId);
    }

    /// @notice Get game state count
    function getGameStateCount() public view returns (uint256) {
        return gameStateCount;
    }

    /// @notice Get trade count
    function getTradeCount() public view returns (uint256) {
        return tradeCount;
    }

    /// @notice Check if trade is revealed
    function isTradeRevealed(uint256 tradeId) public view returns (bool) {
        return infoTrades[tradeId].isRevealed;
    }
}