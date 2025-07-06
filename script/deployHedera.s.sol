// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockToken} from "test/MockToken.sol";
import {LMSRMarketMaker} from "src/LMSRMarketMaker.sol";
import {OracleManager} from "src/OracleManager.sol";

contract DeployMyContract is Script {
    function run() external {
        MockToken token = MockToken(0x6c024E280439EEC7f0e816151ef53659F1155af9); 
        console.log("Deployed MockToken at:", address(token)); 

        LMSRMarketMaker marketMaker = new LMSRMarketMaker(IERC20(token), 0); 
        console.log("Deployed LMSRMarketMaker at:", address(marketMaker)); 

        OracleManager oracleManager = new OracleManager();
        console.log("Deployed OracleManager at:", address(oracleManager)); 


        token.mint(msg.sender, 1_000_000*10**18);
        token.approve(address(marketMaker), 1_000_000*10**18);
        marketMaker.prepareCondition(address(oracleManager), "ETH/BTC", 2);
        marketMaker.initializeMarket(10*10**18, 1_000*10**18);

        oracleManager.registreNewMarket("ETH/BTC", address(marketMaker), 2);

        int256[] memory deltaOutcomeAmounts_ = new int256[](2);
        deltaOutcomeAmounts_[0] = 10*10**18;
        deltaOutcomeAmounts_[1] = 10*10**18;
        marketMaker.makePrediction(deltaOutcomeAmounts_);

        vm.stopBroadcast(); 
    }
} 