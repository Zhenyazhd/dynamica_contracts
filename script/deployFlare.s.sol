// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/src/Script.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {MockToken} from "test/MockToken.sol";
import {LMSRMarketMaker} from "src/LMSRMarketMaker.sol";
import {OracleManager} from "src/OracleManager_flare.sol";
import {DataFeed} from "src/DynamicaFeed.sol";

contract DeployMyContract is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        bytes32[] memory tokens = new bytes32[](2);
        tokens[0] = keccak256(abi.encodePacked("ETH/USD")); //0x01464c522f55534400000000000000000000000000; // FLR/USD
        tokens[1] = keccak256(abi.encodePacked("BTC/USD")); //0x014254432f55534400000000000000000000000000; // BTC/USD
        console.logBytes32(tokens[0]);
        console.logBytes32(tokens[1]);

        OracleManager oracleManager = new OracleManager(0x3d893C53D9e8056135C26C8c638B76C8b60Df726);
        console.log("Deployed OracleManager at:", address(oracleManager));

        DataFeed dataFeed = new DataFeed();
        console.log("Deployed DataFeed at:", address(dataFeed));

        MockToken token = MockToken(0x61cE7ff8792faA0588AD69e22F9b88AAC6f409F7);
        console.log("Deployed MockToken at:", address(token));

        LMSRMarketMaker marketMaker = new LMSRMarketMaker(IERC20(token), 0);
        console.log("Deployed LMSRMarketMaker at:", address(marketMaker));

        token.mint(0xDAc70eD79011695F414E18474868C0cDC808B493, 1_000_000 * 10 ** 18);
        token.approve(address(marketMaker), 1_000_000 * 10 ** 18);
        marketMaker.prepareCondition(address(dataFeed), "Drivers", 5);
        marketMaker.initializeMarket(1000 * 10 ** 18, 1_000 * 10 ** 18);

        dataFeed.registreNewMarket("Drivers", address(marketMaker), 5, tokens);

        oracleManager.addOracle(tokens[0], 0x014554482f55534400000000000000000000000000, 60 * 60 * 24 * 90);
        oracleManager.addOracle(tokens[1], 0x014254432f55534400000000000000000000000000, 60 * 60 * 24 * 90);

        oracleManager.registreNewMarket("ETH/BTC", address(marketMaker), 2, tokens);
    }
}
