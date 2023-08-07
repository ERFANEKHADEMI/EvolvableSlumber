// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ISharesHolder.sol";
import "./interfaces/IEvolutionStrategy.sol";
import "solady/src/utils/LibString.sol";

/**
 * NONE: Staking disabled.
 * CURRENT: Stake linear to the time the token was last time staked.
 * ALIVE: Stake linear to the time the token was staked for the first time.
 * CUMULATIVE: Stake linear to the sum of all staking times. E.g, if you staked
 * for 3 days, unstaked, and restaked for another day, the total stake will
 * be linearly proportional to 4.
 */
enum StakingType {
    NONE, CURRENT, ALIVE, CUMULATIVE
}

struct StakingConfig {
    uint24 
}

/**
 * Note that all those timestamps are enough to calculate any
 * possible staking strategy (any `StakingType`).
 * Note also that the actual total time staked will be:
 *     `totalTimeStaked + (block.timestamp - lastTimeStaked)`
 * Because this value is dynamic and depends on the chain state.
 */
struct StakeTokenInfo {
    bool isStaked;
    uint32 firstTimeStaked;
    uint32 totalTimeStaked;
    uint32 lastTimeStaked;
}

struct EvolutionConfig {
    StakingType evolutionStakeStrategy;
    address evolutionStrategy;
}

struct RewardsConfig {
    StakingType rewardsTakeStrategy;
}

struct GeneralConfig {
    uint256 price;
    string baseUri;
}

contract ImmutableEvolutionArchetype is ERC721A, Ownable {

    mapping (uint256 => StakeTokenInfo) private _tokenIdToStakeInfo;

    EvolutionConfig private _evolutionConfig;
    RewardsConfig private _rewardsConfig;
    GeneralConfig private _config;
    bool private _initialized;

    constructor(
        string memory name,
        string memory ticker
    ) ERC721A(name, ticker) {}
    
    function initialize(
        EvolutionConfig memory evolutionConfig,
        RewardsConfig memory rewardsConfig,
        GeneralConfig memory config 
    ) public onlyOwner {
        _evolutionConfig = evolutionConfig;
        _rewardsConfig = rewardsConfig;
        _config = config;
        _initialized = true;
    }

    function mint(uint16 quantity) external payable {
        require(msg.value >= _config.price * quantity);
        _mint(msg.sender, quantity);
    }

    function stake(uint256 tokenId) public {
        require(ownerOf(tokenId) == msg.sender);
        StakeTokenInfo memory stake = _tokenIdToStakeInfo[tokenId];
        require(!stake.isStaked);
        uint32 currentTime = uint32(block.timestamp);

        if (stake.firstTimeStaked == 0) stake.firstTimeStaked = currentTime;
        stake.lastTimeStaked = currentTime;

        stake.isStaked = true;
        _tokenIdToStakeInfo[tokenId] = stake;
    }

    function unstake(uint256 tokenId) public {
        require(ownerOf(tokenId) == msg.sender);
        StakeTokenInfo memory stake = _tokenIdToStakeInfo[tokenId];
        require(stake.isStaked);

        stake.totalTimeStaked += uint32(block.timestamp) - stake.lastTimeStaked;

        stake.isStaked = false;
        _tokenIdToStakeInfo[tokenId] = stake;
    }

    function getStake(
        uint256 tokenId, StakingType strategy
    ) public view returns (uint256) {
        StakeTokenInfo memory stake = _tokenIdToStakeInfo[tokenId];
        if (strategy == StakingType.CURRENT) 
            return block.timestamp - stake.lastTimeStaked;
        if (strategy == StakingType.ALIVE) 
            return block.timestamp - stake.firstTimeStaked;
        if (strategy == StakingType.CUMULATIVE) 
            return (block.timestamp - stake.lastTimeStaked) + stake.totalTimeStaked;
        return 0;
    }
    
    function getEvolution(uint256 tokenId) public view returns (uint256) {
        uint256 stake = getStake(tokenId, _evolutionConfig.evolutionStakeStrategy);
        return IEvolutionStrategy(_evolutionConfig.evolutionStrategy).getEvolution(stake);
    }

    function tokenURI(uint256 tokenId) 
        public 
        view
        virtual
        override
        returns (string memory)
    {
        if (bytes(_config.baseUri).length == 0) return "";
        return string(abi.encodePacked(
            _config.baseUri,
            LibString.toString(getEvolution(tokenId)),
            "/",
            LibString.toString(tokenId)
        ));
    }

}
